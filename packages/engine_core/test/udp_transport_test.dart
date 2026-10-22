@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_io.dart';
import 'package:test/test.dart';

Future<void> until(bool Function() ok, [int ms = 2000]) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late UdpListener server;
  final accepted = <NetEndpoint>[];
  final opened = <NetEndpoint>[];

  setUp(() async {
    accepted.clear();
    server = await UdpListener.bind(accepted.add);
  });

  tearDown(() async {
    for (final e in opened) {
      e.close();
    }
    opened.clear();
    await server.close();
  });

  Future<NetEndpoint> connect({
    Duration idle = const Duration(seconds: 10),
  }) async {
    final c = await connectUdp('127.0.0.1', server.port, idleTimeout: idle);
    opened.add(c);
    return c;
  }

  test(
    'the first packet introduces the client; messages flow both ways',
    () async {
      final c = await connect();
      await until(() => accepted.length == 1);
      expect(
        accepted,
        hasLength(1),
        reason: 'the open packet alone created the peer',
      );

      final atHost = <Map<String, dynamic>>[];
      final atClient = <Map<String, dynamic>>[];
      accepted.single.onMessage = (m) {
        atHost.add(m);
        accepted.single.send({'echo': m['n']});
      };
      c.onMessage = atClient.add;
      c.send({'n': 1});
      c.send({'n': 2});
      await until(() => atClient.length == 2);
      expect(atHost.map((m) => m['n']), [1, 2]);
      expect(atClient.map((m) => m['echo']), [1, 2]);
      expect(server.peerCount, 1);
    },
  );

  test('two clients are two peers with their own endpoints', () async {
    final a = await connect();
    final b = await connect();
    await until(() => accepted.length == 2);
    final got = <String>[];
    for (var i = 0; i < 2; i++) {
      final host = accepted[i];
      host.onMessage = (m) => host.send({'who': m['name']});
    }
    a.onMessage = (m) => got.add('a:${m['who']}');
    b.onMessage = (m) => got.add('b:${m['who']}');
    a.send({'name': 'A'});
    b.send({'name': 'B'});
    await until(() => got.length == 2);
    expect(got, unorderedEquals(['a:A', 'b:B']));
  });

  test(
    'close tells the other side at once, which fires onClose and forgets the peer',
    () async {
      final c = await connect();
      await until(() => accepted.length == 1);
      var hostClosed = 0;
      accepted.single.onClose = () => hostClosed++;
      c.close();
      await until(() => hostClosed == 1);
      expect(hostClosed, 1);
      expect(server.peerCount, 0);

      final stray = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      stray.send(
        utf8.encode('{"_udp":"bye"}'),
        InternetAddress.loopbackIPv4,
        server.port,
      );
      stray.send(
        utf8.encode('{"_udp":"ka"}'),
        InternetAddress.loopbackIPv4,
        server.port,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        accepted,
        hasLength(1),
        reason: 'goodbyes and keep-alives never create peers',
      );
      stray.close();
    },
  );

  test(
    'a silent peer is dropped after the idle timeout, a chatty-idle one is kept by keep-alives',
    () async {
      final server2 = await UdpListener.bind(
        accepted.add,
        idleTimeout: const Duration(milliseconds: 300),
      );
      addTearDown(server2.close);
      accepted.clear();
      final live = await connectUdp(
        '127.0.0.1',
        server2.port,
        idleTimeout: const Duration(milliseconds: 300),
      );
      opened.add(live);
      await until(() => accepted.length == 1);
      var closed = 0;
      accepted.single.onClose = () => closed++;
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(closed, 0, reason: 'the client\'s keep-alives hold the peer open');

      // A raw sender that says hello once and then goes quiet is dropped.
      final raw = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      raw.send(
        utf8.encode('{"_udp":"open"}'),
        InternetAddress.loopbackIPv4,
        server2.port,
      );
      await until(() => accepted.length == 2);
      var rawClosed = 0;
      accepted.last.onClose = () => rawClosed++;
      await until(() => rawClosed == 1, 1500);
      expect(rawClosed, 1);
      raw.close();
    },
  );

  test(
    'malformed datagrams and oversized messages are counted, not thrown',
    () async {
      final c = await connect() as UdpEndpoint;
      await until(() => accepted.length == 1);
      final raw = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      raw.send(
        utf8.encode('{"_udp":"open"}'),
        InternetAddress.loopbackIPv4,
        server.port,
      );
      await until(() => accepted.length == 2);
      raw.send(
        utf8.encode('not json'),
        InternetAddress.loopbackIPv4,
        server.port,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect((accepted.last as UdpEndpoint).malformedFrames, 1);

      c.send({'blob': 'x' * (udpMaxMessageBytes + 10)});
      expect(c.oversized, 1);
      raw.close();
    },
  );

  test(
    'a HostSession serves a client over UDP: welcome, team and an order that moves a unit',
    () async {
      final hostWorld = World(width: 12, height: 12);
      registerCoreComponents(hostWorld);
      hostWorld.addSystem(
        OrderSystem.withNavigator(
          GridNavigator(cols: 12, rows: 12, terrainCost: (c, r) => 1),
        ),
      );
      final unit = hostWorld.spawn();
      hostWorld.storeOf<Team>().set(unit, Team('red'));
      hostWorld.storeOf<ActionPoints>().set(unit, ActionPoints(6, current: 0));
      hostWorld.storeOf<GridPosition>().set(unit, GridPosition(1, 1));
      final blue = hostWorld.spawn();
      hostWorld.storeOf<Team>().set(blue, Team('blue'));
      hostWorld.storeOf<GridPosition>().set(blue, GridPosition(9, 9));
      startTurnBasedGame(hostWorld, ['red', 'blue']);
      final host = HostSession(world: hostWorld, teams: ['red', 'blue']);
      final udp = await UdpListener.bind(host.accept);
      addTearDown(udp.close);
      final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        hostWorld.step(0.05);
        host.afterStep();
      });
      addTearDown(timer.cancel);

      final clientWorld = World(width: 12, height: 12);
      registerCoreComponents(clientWorld);
      final endpoint = await connectUdp('127.0.0.1', udp.port);
      addTearDown(endpoint.close);
      final session = ClientSession(world: clientWorld, endpoint: endpoint);
      await until(
        () => session.team != null && clientWorld.entities.isAlive(unit),
      );
      expect(session.team, 'red');

      session.sendOrder(unit, const MoveOrder(3, 1));
      await until(() => hostWorld.storeOf<GridPosition>().get(unit)!.col == 3);
      expect(hostWorld.storeOf<GridPosition>().get(unit)!.col, 3);
    },
  );
}
