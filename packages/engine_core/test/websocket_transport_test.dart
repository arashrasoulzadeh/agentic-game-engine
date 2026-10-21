@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_io.dart';
import 'package:test/test.dart';

World _world({bool host = true}) {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  if (host) {
    w.addSystem(
      OrderSystem.withNavigator(
        GridNavigator(cols: 12, rows: 12, terrainCost: (c, r) => 1),
      ),
    );
    installCombat(w);
  }
  return w;
}

EntityId _unit(World w, String team, int c, int r) {
  final e = w.spawn();
  w.storeOf<Team>().set(e, Team(team));
  w.storeOf<ActionPoints>().set(e, ActionPoints(6, current: 0));
  w.storeOf<GridPosition>().set(e, GridPosition(c, r));
  w.storeOf<UnitStats>().set(e, UnitStats(maxHp: 10, attack: 3));
  return e;
}

/// Runs the host loop for [ticks], yielding to the event loop so sockets can move.
Future<void> _pump(World w, HostSession host, int ticks) async {
  for (var i = 0; i < ticks; i++) {
    w.step(0.05);
    host.afterStep();
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late World world;
  late HostSession host;
  late WebSocketListener server;
  final opened = <NetEndpoint>[];

  setUp(() async {
    world = _world();
    host = HostSession(world: world, teams: ['red', 'blue']);
    server = await WebSocketListener.bind(host.accept);
  });

  tearDown(() async {
    for (final e in opened) {
      e.close();
    }
    opened.clear();
    await server.close();
  });

  Future<ClientSession> join() async {
    final endpoint = await connectWebSocket(server.localUrl);
    opened.add(endpoint);
    return ClientSession(world: _world(host: false), endpoint: endpoint);
  }

  test('two players join over a real socket and are assigned teams', () async {
    final a = await join();
    final b = await join();
    await _pump(world, host, 20);
    expect((a.playerId, a.team), (1, 'red'));
    expect((b.playerId, b.team), (2, 'blue'));
    expect(server.port, greaterThan(0));
    expect(server.localUrl, startsWith('ws://127.0.0.1:'));
  });

  test(
    'orders travel to the host and the resulting state replicates back',
    () async {
      final mine = _unit(world, 'red', 1, 1);
      _unit(world, 'blue', 10, 10);
      startTurnBasedGame(world, ['red', 'blue']);
      final a = await join();
      await _pump(world, host, 15);

      a.sendOrder(mine, const MoveOrder(4, 1));
      await _pump(world, host, 40);

      expect(world.storeOf<GridPosition>().get(mine)!.col, 4);
      expect(a.world.storeOf<GridPosition>().get(mine)!.col, 4);
      expect(a.capture().entities, WorldSnapshot.capture(world).entities);
    },
  );

  test('a third connection is told the game is full and closed', () async {
    await join();
    await join();
    final c = await join();
    await _pump(world, host, 20);
    expect(c.rejectedAsFull, isTrue);
    expect(c.connected, isFalse);
    expect(host.players, hasLength(2));
  });

  test(
    'a client that disconnects frees its team and the host hears about it',
    () async {
      final left = <PlayerSlot>[];
      host.onLeft = left.add;
      final a = await join();
      await _pump(world, host, 10);
      a.endpoint.close();
      await _pump(world, host, 15);
      expect(left.single.team, 'red');
      expect(host.players, isEmpty);
      final again = await join();
      await _pump(world, host, 15);
      expect(again.team, 'red');
    },
  );

  test(
    'garbage frames are dropped; the connection and the game survive',
    () async {
      final mine = _unit(world, 'red', 1, 1);
      _unit(world, 'blue', 10, 10);
      startTurnBasedGame(world, ['red', 'blue']);
      final raw = await WebSocket.connect(server.localUrl);
      addTearDown(() => raw.close());
      await _pump(world, host, 8);
      raw.add('this is not json');
      raw.add('[1,2,3]');
      raw.add('"just a string"');
      raw.add(<int>[1, 2, 3]); // a binary frame
      await _pump(world, host, 8);
      expect(host.players, hasLength(1));

      raw.add(
        '{"type":"order","unit":$mine,"order":{"type":"move","col":3,"row":1}}',
      );
      await _pump(world, host, 15);
      expect(
        world.storeOf<GridPosition>().get(mine)!.col,
        3,
        reason: 'the connection still works after the garbage',
      );
    },
  );

  test('WebSocketEndpoint counts the frames it dropped', () async {
    final received = Completer<WebSocketEndpoint>();
    final tmp = await WebSocketListener.bind(
      (e) => received.complete(e as WebSocketEndpoint),
    );
    addTearDown(tmp.close);
    final raw = await WebSocket.connect(tmp.localUrl);
    addTearDown(() => raw.close());
    final endpoint = await received.future;
    final messages = <Map<String, dynamic>>[];
    endpoint.onMessage = messages.add;
    raw
      ..add('nope')
      ..add('[]')
      ..add(<int>[0])
      ..add('{"ok":true}');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(endpoint.malformedFrames, 3);
    expect(messages, [
      {'ok': true},
    ]);
  });

  test('plain HTTP requests are refused with 426', () async {
    final client = HttpClient();
    addTearDown(() => client.close(force: true));
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
    );
    final response = await request.close();
    expect(response.statusCode, HttpStatus.upgradeRequired);
    await response.drain<void>();
  });

  test(
    'closing an endpoint twice is harmless and sends after close are ignored',
    () async {
      final a = await join();
      await _pump(world, host, 5);
      a.endpoint.close();
      a.endpoint.close();
      a.sendOrder(0, const MoveOrder(1, 1));
      await _pump(world, host, 5);
    },
  );
}
