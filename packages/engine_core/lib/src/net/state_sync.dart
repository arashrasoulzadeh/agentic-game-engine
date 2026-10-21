import '../ecs/entity.dart';
import '../ecs/world.dart';
import 'lag_compensation.dart';
import 'world_snapshot.dart';

/// Authoritative-server state replication: each tick, send every client what
/// changed since the last state *it confirmed*, falling back to a full snapshot
/// for a new client.
///
/// Deltas are taken against the client's last **acknowledged** tick, not the last
/// tick sent. On an unreliable link a delta against "the previous packet" breaks
/// the moment one packet is lost; one against an acknowledged baseline is always
/// applicable, at the cost of slightly larger deltas while acks are in flight.
/// Decides whether a client may see an entity: gets its id and its serialized components
/// (the same JSON that goes over the wire). Return false to keep it out of that client's
/// updates. See [nearbyInterest] for the common "only what is close to me" rule.
typedef InterestFilter =
    bool Function(EntityId id, Map<String, dynamic> components);

/// An [InterestFilter] that shows a client entities within [radius] world units of the point
/// [center] returns (typically its camera or its units' centroid), plus every entity with no
/// `position` (global things such as a treasury or match state) and the ids in [always].
///
/// [center] is called once per broadcast per client; returning null shows everything
/// (nothing to centre on yet). Distances use the serialized `position` (`x`, `y`), so the rule
/// depends only on what is sent.
InterestFilter Function() nearbyInterest({
  required ({double x, double y})? Function() center,
  required double radius,
  Iterable<EntityId> Function()? always,
}) {
  return () {
    final c = center();
    final keep = always == null ? const <EntityId>{} : always().toSet();
    return (id, components) {
      if (c == null || keep.contains(id)) return true;
      final p = components['position'];
      if (p is! Map) return true;
      final dx = (p['x'] as num).toDouble() - c.x;
      final dy = (p['y'] as num).toDouble() - c.y;
      return dx * dx + dy * dy <= radius * radius;
    };
  };
}

class StateSyncServer {
  StateSyncServer({required this.world, this.maxHistory = 128});

  final World world;
  final int maxHistory;

  final Map<int, void Function(Map<String, dynamic>)> _clients = {};
  final Map<int, int> _acked = {};
  final Map<int, WorldSnapshot> _history = {};
  final Map<int, InterestFilter Function()> _interest = {};

  /// What each interest-filtered client was actually sent, per tick. A delta must be taken
  /// against *that*, not against the full world: an entity that left the client's view has to
  /// show up as removed, which only a record of what the client holds can tell.
  final Map<int, Map<int, WorldSnapshot>> _sent = {};

  /// Called with `(clientId, message)` for each client `input` message.
  void Function(int client, Map<String, dynamic> message)? onInput;

  int fullSnapshotsSent = 0;
  int deltasSent = 0;

  /// Registers a client; [send] delivers a message to it.
  ///
  /// With [interest] the client is only sent entities that rule admits (interest
  /// management: less bandwidth, and a client cannot see what it should not, e.g. units in
  /// fog). It is a factory so it can be re-evaluated every broadcast, as the viewpoint moves;
  /// see [nearbyInterest].
  void addClient(
    int id,
    void Function(Map<String, dynamic>) send, {
    InterestFilter Function()? interest,
  }) {
    _clients[id] = send;
    if (interest != null) {
      _interest[id] = interest;
      _sent[id] = {};
    }
  }

  void removeClient(int id) {
    _clients.remove(id);
    _acked.remove(id);
    _interest.remove(id);
    _sent.remove(id);
  }

  /// Sends the current state to every client. Call once per tick (or every few
  /// ticks to reduce bandwidth).
  void broadcast() {
    final now = WorldSnapshot.capture(world);
    _history[now.tick] = now;
    for (final entry in _clients.entries) {
      final rule = _interest[entry.key];
      final view = rule == null ? now : _filtered(now, rule());
      final sent = _sent[entry.key];
      sent?[view.tick] = view;
      final base = sent == null
          ? _history[_acked[entry.key]]
          : sent[_acked[entry.key]];
      if (base == null) {
        fullSnapshotsSent++;
        entry.value({'type': 'snapshot', 'state': view.toJson()});
      } else {
        deltasSent++;
        entry.value({
          'type': 'delta',
          'delta': WorldDelta.between(base, view).toJson(),
        });
      }
    }
    _prune();
  }

  /// Handles a message from client [id]: `ack` or `input`.
  void handle(int id, Map<String, dynamic> message) {
    switch (message['type']) {
      case 'ack':
        final tick = (message['tick'] as num).toInt();
        if (_history.containsKey(tick) && tick > (_acked[id] ?? -1))
          _acked[id] = tick;
      case 'input':
        onInput?.call(id, message);
    }
  }

  WorldSnapshot _filtered(WorldSnapshot full, InterestFilter keep) =>
      WorldSnapshot(full.tick, {
        for (final e in full.entities.entries)
          if (keep(e.key, e.value)) e.key: e.value,
      });

  void _prune() {
    final keepFrom = world.tick - maxHistory;
    final pinned = _acked.values.toSet();
    _history.removeWhere((t, _) => t < keepFrom && !pinned.contains(t));
    for (final entry in _sent.entries) {
      final pin = _acked[entry.key];
      entry.value.removeWhere((t, _) => t < keepFrom && t != pin);
    }
  }
}

/// Applies a server's snapshots and deltas to a local world and acknowledges
/// them, keeping a position history so remote entities can be drawn smoothly
/// between updates.
class StateSyncClient {
  StateSyncClient({
    required this.world,
    required this.send,
    this.keepBaselines = 32,
    PositionHistory? history,
  }) : history = history ?? PositionHistory();

  final World world;

  /// Sends a message to the server.
  final void Function(Map<String, dynamic>) send;
  final int keepBaselines;
  final PositionHistory history;

  final Map<int, WorldSnapshot> _baselines = {};

  /// Tick of the newest state applied, or null before the first.
  int? latestTick;

  /// Deltas dropped because their baseline was no longer held.
  int unusableDeltas = 0;

  /// Handles a `snapshot` or `delta` message from the server.
  void receive(Map<String, dynamic> message) {
    final WorldSnapshot snapshot;
    switch (message['type']) {
      case 'snapshot':
        snapshot = WorldSnapshot.fromJson(
          (message['state'] as Map).cast<String, dynamic>(),
        );
      case 'delta':
        final delta = WorldDelta.fromJson(
          (message['delta'] as Map).cast<String, dynamic>(),
        );
        final base = _baselines[delta.baseTick];
        if (base == null) {
          unusableDeltas++;
          return;
        }
        snapshot = delta.applyTo(base);
      default:
        return;
    }
    // Out-of-order arrival (a reordered older packet) must not rewind the world.
    if (latestTick != null && snapshot.tick < latestTick!) return;
    _baselines[snapshot.tick] = snapshot;
    _baselines.removeWhere((t, _) => t < snapshot.tick - keepBaselines);
    latestTick = snapshot.tick;
    snapshot.restoreInto(world);
    history.recordSnapshot(snapshot);
    send({'type': 'ack', 'tick': snapshot.tick});
  }

  /// Sends a player input for [tick] to the server.
  void sendInput(int player, int tick, Map<String, dynamic> input) =>
      send({'type': 'input', 'player': player, 'tick': tick, 'input': input});
}
