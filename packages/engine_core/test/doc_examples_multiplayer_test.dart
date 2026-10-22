@TestOn('vm')
library;

// The host and client of docs/tutorials/04-multiplayer.md, executed on an ephemeral port so the
// tutorial cannot drift from the API.
import 'dart:async';

import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_io.dart';
import 'package:test/test.dart';

void main() {
  test(
    'the tutorial host accepts a client that welcomes itself, orders a unit and measures rtt',
    () async {
      // --- host.dart (port 4040 -> ephemeral) ---
      final world = World(width: 12, height: 12);
      registerCoreComponents(world);
      world.addSystem(
        OrderSystem.withNavigator(
          GridNavigator(cols: 12, rows: 12, terrainCost: (c, r) => 1),
        ),
      );
      installCombat(world);
      for (var i = 0; i < 3; i++) {
        for (final (team, col) in [('red', 1), ('blue', 10)]) {
          final e = world.spawn();
          world.storeOf<Team>().set(e, Team(team));
          world.storeOf<ActionPoints>().set(e, ActionPoints(6, current: 0));
          world.storeOf<GridPosition>().set(e, GridPosition(col, 3 + i));
          world.storeOf<UnitStats>().set(e, UnitStats(maxHp: 10, attack: 3));
        }
      }
      startTurnBasedGame(world, ['red', 'blue']);
      final host = HostSession(world: world, teams: ['red', 'blue']);
      final server = await WebSocketListener.bind(host.accept);
      final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
        world.step(0.05);
        host.afterStep();
      });
      addTearDown(() async {
        timer.cancel();
        await server.close();
      });

      // --- client.dart ---
      final clientWorld = World(width: 12, height: 12);
      registerCoreComponents(clientWorld);
      final endpoint = await connectWebSocket(server.localUrl);
      addTearDown(endpoint.close);
      final sw = Stopwatch()..start();
      final session = ClientSession(
        world: clientWorld,
        endpoint: endpoint,
        clock: () => sw.elapsedMilliseconds,
      );
      var welcomed = false;
      session.onWelcome = () => welcomed = true;
      session.onRejected = (unit, reason) {};

      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(welcomed, isTrue);
      expect(session.team, 'red');

      final mine = [
        for (final e in clientWorld.entities.all)
          if (clientWorld.storeOf<Team>().get(e)?.id == session.team) e,
      ];
      expect(mine, hasLength(3));
      session.sendOrder(mine.first, const MoveOrder(4, 3));
      session.ping();
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(session.rttMs, isNotNull);
      expect(
        world.storeOf<GridPosition>().get(mine.first)!.col,
        4,
        reason: 'the order reached the host and moved the unit',
      );
    },
  );
}
