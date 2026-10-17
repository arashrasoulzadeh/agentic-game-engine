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
class StateSyncServer {
  StateSyncServer({required this.world, this.maxHistory = 128});

  final World world;
  final int maxHistory;

  final Map<int, void Function(Map<String, dynamic>)> _clients = {};
  final Map<int, int> _acked = {};
  final Map<int, WorldSnapshot> _history = {};

  /// Called with `(clientId, message)` for each client `input` message.
  void Function(int client, Map<String, dynamic> message)? onInput;

  int fullSnapshotsSent = 0;
  int deltasSent = 0;

  /// Registers a client; [send] delivers a message to it.
  void addClient(int id, void Function(Map<String, dynamic>) send) => _clients[id] = send;

  void removeClient(int id) {
    _clients.remove(id);
    _acked.remove(id);
  }

  /// Sends the current state to every client. Call once per tick (or every few
  /// ticks to reduce bandwidth).
  void broadcast() {
    final now = WorldSnapshot.capture(world);
    _history[now.tick] = now;
    for (final entry in _clients.entries) {
      final base = _history[_acked[entry.key]];
      if (base == null) {
        fullSnapshotsSent++;
        entry.value({'type': 'snapshot', 'state': now.toJson()});
      } else {
        deltasSent++;
        entry.value({'type': 'delta', 'delta': WorldDelta.between(base, now).toJson()});
      }
    }
    _prune();
  }

  /// Handles a message from client [id]: `ack` or `input`.
  void handle(int id, Map<String, dynamic> message) {
    switch (message['type']) {
      case 'ack':
        final tick = (message['tick'] as num).toInt();
        if (_history.containsKey(tick) && tick > (_acked[id] ?? -1)) _acked[id] = tick;
      case 'input':
        onInput?.call(id, message);
    }
  }

  void _prune() {
    final keepFrom = world.tick - maxHistory;
    final pinned = _acked.values.toSet();
    _history.removeWhere((t, _) => t < keepFrom && !pinned.contains(t));
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
        snapshot = WorldSnapshot.fromJson((message['state'] as Map).cast<String, dynamic>());
      case 'delta':
        final delta = WorldDelta.fromJson((message['delta'] as Map).cast<String, dynamic>());
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
