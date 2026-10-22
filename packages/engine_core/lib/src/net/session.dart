import 'dart:async';

import '../ecs/entity.dart';
import '../ecs/world.dart';
import '../turn/order.dart';
import '../turn/order_system.dart';
import '../turn/turn_components.dart';
import 'net_endpoint.dart';
import 'state_sync.dart';
import 'world_snapshot.dart';

/// One connected player, as the host sees them.
class PlayerSlot {
  PlayerSlot(this.id, this.team, this.endpoint);

  final int id;

  /// The team this player commands. Assigned by the host; the player cannot
  /// choose or change it.
  final String team;
  final NetEndpoint endpoint;
  String? name;
}

/// The authoritative side of a multiplayer game: accepts players, assigns each a
/// team, validates the orders they send, and replicates the world to them.
///
/// **The host is the only simulation that counts.** A client never tells the host
/// what happened ("my unit moved here") - it asks for something to happen (an
/// order), and the host runs `submitOrder` against the real world. A modified
/// client can therefore at worst send orders the rules would accept from that team
/// anyway: it cannot move another team's units, act out of turn or teleport.
///
/// Wire protocol (all JSON): host -> client `welcome`, `start`, `full`, `pong`,
/// `rejected`, `snapshot`, `delta`; client -> host `ping`, `order`, `ack`.
class HostSession {
  HostSession({
    required this.world,
    required this.teams,
    this.syncEveryTicks = 1,
    StateSyncServer? sync,
    this.authenticate,
    this.authTimeoutTicks = 200,
  }) : assert(teams.isNotEmpty, 'a game needs at least one playable team'),
       assert(syncEveryTicks >= 1),
       sync = sync ?? StateSyncServer(world: world);

  final World world;

  /// The teams humans can take, in the order they are handed out.
  final List<String> teams;

  /// Replicate state every this many ticks (>1 saves bandwidth at the cost of
  /// latency).
  final int syncEveryTicks;
  final StateSyncServer sync;

  /// When set, a connection must prove itself before it gets a team: it is held, hears nothing and takes no
  /// slot until its first message, `{"type": "hello", "token": ...}`, passes this check (given the token and
  /// the optional `name`). A refusal sends `denied` and closes. May be async (a database or token service).
  ///
  /// This is the host's gate against strangers and does not encrypt anything: serve over `wss://` so the
  /// token is not readable in transit.
  final FutureOr<bool> Function(String? token, String? name)? authenticate;

  /// Ticks (calls to [afterStep]) a connection may stay unauthenticated before it is dropped.
  final int authTimeoutTicks;

  final Map<NetEndpoint, int> _pending = {};

  /// How many connections are waiting to authenticate (for tests and monitoring).
  int get pendingCount => _pending.length;

  final Map<int, PlayerSlot> players = {};
  int _nextId = 1;

  /// True once [start] has been called.
  bool started = false;

  void Function(PlayerSlot player)? onJoined;
  void Function(PlayerSlot player)? onLeft;

  /// Orders refused so far, as `(player id, reason)` - for logging and tests.
  final List<(int, String)> rejections = [];

  int _ticksSinceSync = 0;

  /// Takes a new connection. Returns the player slot, or null (after telling the
  /// peer `full` and closing it) when every team is already taken.
  ///
  /// With [authenticate] set, returns null at once and admits the connection later if it passes.
  PlayerSlot? accept(NetEndpoint endpoint) {
    if (authenticate == null) return _admit(endpoint);
    _pending[endpoint] = 0;
    endpoint.onMessage = (m) {
      if (m['type'] == 'hello' && _pending.containsKey(endpoint)) {
        _check(endpoint, m['token'] as String?, m['name'] as String?);
      }
    };
    endpoint.onClose = () => _pending.remove(endpoint);
    return null;
  }

  Future<void> _check(NetEndpoint endpoint, String? token, String? name) async {
    bool ok;
    try {
      ok = await authenticate!(token, name);
    } on Object {
      ok = false;
    }
    if (_pending.remove(endpoint) == null)
      return; // dropped or timed out meanwhile
    if (!ok) {
      endpoint.send({'type': 'denied'});
      endpoint.close();
      return;
    }
    final slot = _admit(endpoint);
    if (slot != null) slot.name = name;
  }

  PlayerSlot? _admit(NetEndpoint endpoint) {
    final taken = {for (final p in players.values) p.team};
    final free = teams.where((t) => !taken.contains(t));
    if (free.isEmpty) {
      endpoint.send({'type': 'full'});
      endpoint.close();
      return null;
    }
    final slot = PlayerSlot(_nextId++, free.first, endpoint);
    players[slot.id] = slot;
    sync.addClient(slot.id, endpoint.send);
    endpoint.onMessage = (m) => _handle(slot, m);
    endpoint.onClose = () => _drop(slot);
    endpoint.send({
      'type': 'welcome',
      'player': slot.id,
      'team': slot.team,
      'teams': teams,
      'tick': world.tick,
      'started': started,
    });
    onJoined?.call(slot);
    return slot;
  }

  /// Marks the game started and tells everyone.
  void start() {
    started = true;
    for (final p in players.values) {
      p.endpoint.send({'type': 'start', 'tick': world.tick});
    }
  }

  /// Call once after every `world.step`: replicates state on schedule.
  void afterStep() {
    if (_pending.isNotEmpty) {
      for (final e in _pending.keys.toList()) {
        final waited = _pending[e]! + 1;
        if (waited > authTimeoutTicks) {
          _pending.remove(e);
          e.send({'type': 'denied'});
          e.close();
        } else {
          _pending[e] = waited;
        }
      }
    }
    _ticksSinceSync++;
    if (_ticksSinceSync >= syncEveryTicks) {
      _ticksSinceSync = 0;
      sync.broadcast();
    }
  }

  void _handle(PlayerSlot slot, Map<String, dynamic> message) {
    switch (message['type']) {
      case 'hello':
        slot.name = message['name'] as String?;
      case 'ping':
        slot.endpoint.send({
          'type': 'pong',
          't': message['t'],
          'tick': world.tick,
        });
      case 'order':
        _order(slot, message);
      default:
        sync.handle(slot.id, message);
    }
  }

  void _order(PlayerSlot slot, Map<String, dynamic> message) {
    String reject(String reason) {
      rejections.add((slot.id, reason));
      slot.endpoint.send({
        'type': 'rejected',
        'unit': message['unit'],
        'reason': reason,
      });
      return reason;
    }

    final unit = message['unit'];
    if (unit is! int || !world.entities.isAlive(unit)) {
      reject('no such unit');
      return;
    }
    if (world.storeOf<Team>().get(unit)?.id != slot.team) {
      reject('not your unit');
      return;
    }
    final Order order;
    try {
      order = Order.fromJson((message['order'] as Map).cast<String, dynamic>());
    } on FormatException {
      reject('malformed order');
      return;
    } on TypeError {
      reject('malformed order');
      return;
    }
    if (!submitOrder(world, unit, order)) reject('order not allowed now');
  }

  void _drop(PlayerSlot slot) {
    if (players.remove(slot.id) == null) return;
    sync.removeClient(slot.id);
    onLeft?.call(slot);
  }
}

/// The player's side: sends orders, applies the host's state, and measures the
/// connection.
///
/// It owns no rules. The world it holds is a *mirror* of the host's, overwritten by
/// each snapshot/delta; show it, do not simulate it (unless you also run
/// prediction with a `RollbackSession`).
class ClientSession {
  ClientSession({
    required this.world,
    required this.endpoint,
    this.clock,
    StateSyncClient? sync,
    String? token,
    String? name,
  }) : sync = sync ?? StateSyncClient(world: world, send: endpoint.send) {
    endpoint.onMessage = _handle;
    endpoint.onClose = () {
      connected = false;
      onDisconnected?.call();
    };
    if (token != null || name != null) {
      endpoint.send({
        'type': 'hello',
        if (token != null) 'token': token,
        if (name != null) 'name': name,
      });
    }
  }

  final World world;
  final NetEndpoint endpoint;
  final StateSyncClient sync;

  /// Milliseconds on any monotonic clock (`Stopwatch.elapsedMilliseconds`, a game
  /// timer). It is a function, evaluated at the instant a ping is sent and at the
  /// instant its pong *arrives*, because only the session knows when the transport
  /// delivered the message. Null disables latency measurement. Injected rather than
  /// read from the wall clock so tests and replays stay deterministic.
  final int Function()? clock;

  /// Assigned by the host after connecting; null until `welcome` arrives.
  int? playerId;
  String? team;
  List<String> teams = const [];

  bool connected = true;
  bool started = false;

  /// True if the host turned us away because every team was taken.
  bool rejectedAsFull = false;

  /// True if the host refused our credentials (see `HostSession.authenticate`).
  bool denied = false;

  /// Round-trip time of the latest ping, in milliseconds.
  double? rttMs;

  int? _serverTickAtPong;
  int? _pongReceivedAtMs;

  void Function()? onWelcome;
  void Function()? onStart;
  void Function()? onDisconnected;

  /// Called with `(unit, reason)` when the host refuses one of our orders.
  void Function(int unit, String reason)? onRejected;

  /// Asks the host to give [unit] an [order]. Fire-and-forget: success shows up in
  /// the replicated state, refusal arrives via [onRejected].
  void sendOrder(EntityId unit, Order order) =>
      endpoint.send({'type': 'order', 'unit': unit, 'order': order.toJson()});

  /// Sends a latency probe stamped with [clock]. A no-op without a clock.
  void ping() {
    final now = clock?.call();
    if (now != null) endpoint.send({'type': 'ping', 't': now});
  }

  /// Best estimate of the host's current tick: the tick reported by the last
  /// pong, advanced by the time since it arrived plus half the round trip (the
  /// one-way trip the pong's value has already aged by).
  double? estimatedServerTick(double fixedDt) {
    final tick = _serverTickAtPong,
        at = _pongReceivedAtMs,
        rtt = rttMs,
        now = clock?.call();
    if (tick == null || at == null || rtt == null || now == null) return null;
    return tick + (now - at + rtt / 2) / (fixedDt * 1000);
  }

  void _handle(Map<String, dynamic> m) {
    switch (m['type']) {
      case 'welcome':
        playerId = (m['player'] as num).toInt();
        team = m['team'] as String;
        teams = [for (final t in (m['teams'] as List)) t as String];
        started = m['started'] as bool? ?? false;
        onWelcome?.call();
      case 'full':
        rejectedAsFull = true;
      case 'denied':
        denied = true;
      case 'start':
        started = true;
        onStart?.call();
      case 'pong':
        // Without a clock we cannot measure anything, so leave the estimates
        // unset rather than invent a zero round trip.
        final now = clock?.call();
        if (now == null) return;
        _pongReceivedAtMs = now;
        rttMs = (now - (m['t'] as num).toInt()).toDouble();
        _serverTickAtPong = (m['tick'] as num).toInt();
      case 'rejected':
        onRejected?.call(
          (m['unit'] as num?)?.toInt() ?? -1,
          m['reason'] as String? ?? 'rejected',
        );
      case 'snapshot' || 'delta':
        sync.receive(m);
    }
  }

  /// The mirrored world as a snapshot, for debugging and tests.
  WorldSnapshot capture() => WorldSnapshot.capture(world);
}
