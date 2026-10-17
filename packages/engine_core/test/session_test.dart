import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

const _dt = 1 / 20;

GridNavigator _nav() => GridNavigator(cols: 12, rows: 12, terrainCost: (c, r) => 1);

World _hostWorld() {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  w.addSystem(OrderSystem.withNavigator(_nav()));
  installCombat(w);
  return w;
}

World _clientWorld() {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  return w;
}

EntityId _unit(World w, String team, int c, int r) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(5, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: 10, attack: 3));
  return e;
}

class _Rig {
  _Rig({int latency = 1, double drop = 0, List<String> teams = const ['red', 'blue']})
      : world = _hostWorld() {
    host = HostSession(world: world, teams: teams);
    this.latency = latency;
    this.drop = drop;
  }

  final World world;
  late final HostSession host;
  late final int latency;
  late final double drop;
  final List<LoopbackLink> links = [];
  final List<ClientSession> clients = [];
  int _seed = 1;

  ClientSession connect() {
    final link = LoopbackLink(latencyTicks: latency, dropRate: drop, seed: _seed++);
    links.add(link);
    // The client attaches before the host accepts, as on a real socket where the
    // connection exists on both sides before the first message is sent.
    final client = ClientSession(world: _clientWorld(), endpoint: link.b, clock: () => world.tick * 50);
    clients.add(client);
    host.accept(link.a);
    return client;
  }

  /// One simulation tick on the host, then a network tick for every link.
  void tick() {
    world.step(_dt);
    host.afterStep();
    for (final l in links) {
      l.advance();
    }
  }

  void run(int ticks) {
    for (var i = 0; i < ticks; i++) {
      tick();
    }
  }
}

void main() {
  group('joining', () {
    test('players are welcomed with distinct ids and the first free team', () {
      final rig = _Rig();
      final a = rig.connect(), b = rig.connect();
      rig.run(3);
      expect((a.playerId, a.team), (1, 'red'));
      expect((b.playerId, b.team), (2, 'blue'));
      expect(a.teams, ['red', 'blue']);
      expect(rig.host.players.keys, [1, 2]);
    });

    test('a third player is turned away', () {
      final rig = _Rig();
      rig.connect();
      rig.connect();
      final c = rig.connect();
      rig.run(3);
      expect(c.rejectedAsFull, isTrue);
      expect(c.playerId, isNull);
      expect(c.connected, isFalse);
      expect(rig.host.players, hasLength(2));
    });

    test('leaving frees the team for the next joiner and notifies the host', () {
      final rig = _Rig();
      final left = <PlayerSlot>[];
      rig.host.onLeft = left.add;
      final a = rig.connect();
      rig.connect();
      rig.run(2);
      a.endpoint.close();
      expect(left.single.team, 'red');
      final c = rig.connect();
      rig.run(3);
      expect(c.team, 'red');
      expect(rig.host.sync.fullSnapshotsSent, greaterThan(0));
    });

    test('onJoined fires, hello records the name, and start reaches everyone', () {
      final rig = _Rig();
      final joined = <int>[];
      rig.host.onJoined = (p) => joined.add(p.id);
      final started = <bool>[];
      final a = rig.connect();
      a.onStart = () => started.add(true);
      a.endpoint.send({'type': 'hello', 'name': 'Ada'});
      rig.run(3);
      expect(joined, [1]);
      expect(rig.host.players[1]!.name, 'Ada');
      expect(a.started, isFalse);
      rig.host.start();
      rig.run(3);
      expect(a.started, isTrue);
      expect(started, [true]);
      expect(rig.connect().started, isFalse, reason: 'welcome reports the state at join time...');
      rig.run(3);
      expect(rig.clients.last.started, isTrue, reason: '...which is started by then');
    });
  });

  group('orders', () {
    test('a player orders their own unit; the host simulates it and the client sees the result', () {
      final rig = _Rig();
      final mine = _unit(rig.world, 'red', 1, 1);
      _unit(rig.world, 'blue', 10, 10);
      startTurnBasedGame(rig.world, ['red', 'blue']);
      final a = rig.connect();
      rig.run(4);

      a.sendOrder(mine, const MoveOrder(4, 1));
      rig.run(8);
      expect(rig.world.storeOf<GridPosition>().get(mine)!.col, 4);
      expect(a.world.storeOf<GridPosition>().get(mine)!.col, 4, reason: 'replicated to the client');
      expect(rig.host.rejections, isEmpty);
    });

    test('ordering someone else\'s unit, a ghost, garbage or out of turn is refused', () {
      final rig = _Rig();
      final red = _unit(rig.world, 'red', 1, 1);
      final blue = _unit(rig.world, 'blue', 10, 10);
      startTurnBasedGame(rig.world, ['red', 'blue']);
      final a = rig.connect(); // red
      rig.connect(); // blue
      final reasons = <String>[];
      a.onRejected = (unit, reason) => reasons.add(reason);
      rig.run(4);

      a.sendOrder(blue, const MoveOrder(9, 9));
      a.sendOrder(9999, const MoveOrder(1, 1));
      a.endpoint.send({'type': 'order', 'unit': red, 'order': {'type': 'teleport'}});
      a.endpoint.send({'type': 'order', 'unit': red, 'order': 'nonsense'});
      endTurn(rig.world); // now blue's turn: red may not act
      a.sendOrder(red, const MoveOrder(2, 2));
      rig.run(6);

      expect(reasons, ['not your unit', 'no such unit', 'malformed order', 'malformed order', 'order not allowed now']);
      expect(rig.world.storeOf<GridPosition>().get(blue)!.col, 10);
      expect(rig.world.storeOf<GridPosition>().get(red)!.col, 1);
      expect(rig.host.rejections, hasLength(5));
    });
  });

  group('state replication', () {
    test('both players converge on the host over a lossy, laggy link', () {
      final rig = _Rig(latency: 2, drop: 0.25);
      final reds = [for (var i = 0; i < 3; i++) _unit(rig.world, 'red', 1, 2 + i)];
      final blues = [for (var i = 0; i < 3; i++) _unit(rig.world, 'blue', 10, 2 + i)];
      startTurnBasedGame(rig.world, ['red', 'blue']);
      final a = rig.connect(), b = rig.connect();
      rig.run(6);

      for (final r in reds) {
        a.sendOrder(r, MoveOrder(5, rig.world.storeOf<GridPosition>().get(r)!.row));
      }
      rig.run(10);
      endTurn(rig.world);
      for (final bl in blues) {
        b.sendOrder(bl, MoveOrder(6, rig.world.storeOf<GridPosition>().get(bl)!.row));
      }
      rig.run(60);

      final truth = WorldSnapshot.capture(rig.world).entities;
      expect(a.capture().entities, truth);
      expect(b.capture().entities, truth);
    });

    test('syncEveryTicks throttles broadcasts', () {
      final w = _hostWorld();
      final host = HostSession(world: w, teams: ['red'], syncEveryTicks: 4);
      final link = LoopbackLink();
      host.accept(link.a);
      ClientSession(world: _clientWorld(), endpoint: link.b);
      for (var i = 0; i < 12; i++) {
        w.step(_dt);
        host.afterStep();
        link.advance();
      }
      expect(host.sync.fullSnapshotsSent + host.sync.deltasSent, 3);
    });
  });

  group('clock sync', () {
    test('ping/pong measures the round trip and estimates the host tick', () {
      // 20 Hz: one tick = 50 ms, and the injected clock is the host tick count.
      final rig = _Rig(latency: 3);
      final a = rig.connect();
      rig.run(4);

      a.ping();
      rig.run(8);
      expect(a.rttMs, 300, reason: '3 ticks each way = 6 ticks = 300 ms');
      final est = a.estimatedServerTick(_dt)!;
      expect(est, closeTo(rig.world.tick, 1.5), reason: 'within a tick or two of the truth');
    });

    test('the estimate keeps advancing between pongs', () {
      final rig = _Rig(latency: 2);
      final a = rig.connect();
      rig.run(3);
      a.ping();
      rig.run(6);
      final before = a.estimatedServerTick(_dt)!;
      rig.run(10);
      expect(a.estimatedServerTick(_dt)! - before, closeTo(10, 0.01));
    });

    test('without a clock there is no measurement and ping sends nothing', () {
      final w = _hostWorld();
      final host = HostSession(world: w, teams: ['red']);
      final link = LoopbackLink();
      final client = ClientSession(world: _clientWorld(), endpoint: link.b);
      host.accept(link.a);
      final sentBefore = link.sent;
      client.ping();
      expect(link.sent, sentBefore, reason: 'no clock, so no ping goes out');
      for (var i = 0; i < 4; i++) {
        w.step(_dt);
        host.afterStep();
        link.advance();
      }
      expect(client.rttMs, isNull);
      expect(client.estimatedServerTick(_dt), isNull);
    });

    test('a pong that arrives with no clock is ignored rather than inventing a zero round trip', () {
      final w = _hostWorld();
      final host = HostSession(world: w, teams: ['red']);
      final link = LoopbackLink();
      final client = ClientSession(world: _clientWorld(), endpoint: link.b);
      host.accept(link.a);
      link.a.send({'type': 'pong', 't': 5, 'tick': 99});
      link.advance();
      expect(client.rttMs, isNull);
      client.endpoint.send({'type': 'who knows'});
      link.advance();
    });
  });

  test('disconnect notifies the client', () {
    final rig = _Rig();
    final a = rig.connect();
    var dropped = 0;
    a.onDisconnected = () => dropped++;
    rig.run(2);
    rig.host.players[1]!.endpoint.close();
    expect(a.connected, isFalse);
    expect(dropped, 1);
  });

  test('closing an endpoint stops messages in both directions', () {
    final link = LoopbackLink();
    var got = 0;
    link.b.onMessage = (_) => got++;
    link.a.send({'x': 1});
    link.a.close();
    link.a.close();
    link.a.send({'x': 2});
    link.b.send({'x': 3});
    link.advance();
    expect(got, 1, reason: 'only the message sent before the close');
  });
}
