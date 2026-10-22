import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_strategy/engine_strategy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

World _host() {
  final w = World(width: 320, height: 320);
  registerCoreComponents(w);
  registerFlutterComponents(w);
  w.addSystem(
    OrderSystem.withNavigator(
      GridNavigator(cols: 10, rows: 10, terrainCost: (_, _) => 1),
    ),
  );
  installCombat(w);
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

void main() {
  testWidgets(
    'connects, mirrors the host, selects a unit and sends move and attack orders',
    (tester) async {
      final host = _host();
      final mine = _unit(host, 'red', 1, 1);
      final foe = _unit(host, 'blue', 4, 1);
      startTurnBasedGame(host, ['red', 'blue']);
      final hostSession = HostSession(world: host, teams: ['red', 'blue']);
      final link = LoopbackLink();
      hostSession.accept(link.a);

      final key = GlobalKey<OnlineStrategyViewState>();
      var welcomed = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 320,
            height: 320,
            child: OnlineStrategyView(
              key: key,
              endpoint: link.b,
              atlasRegistry: AtlasRegistry(),
              gridCols: 10,
              gridRows: 10,
              cellSize: 32,
              onWelcome: (_) => welcomed++,
              connectingBuilder: (_) =>
                  const Text('connecting', key: Key('wait')),
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('wait')), findsOneWidget);

      void network() {
        host.step(0.05);
        hostSession.afterStep();
        link.advance();
      }

      for (var i = 0; i < 10; i++) {
        network();
      }
      await tester.pump();
      expect(welcomed, 1);
      expect(find.byKey(const Key('wait')), findsNothing);
      final view = key.currentState!;
      expect(view.session.team, 'red');
      expect(
        view.world.entities.all,
        containsAll([mine, foe]),
        reason: 'the mirror has the host\'s units',
      );

      view.tapCell(7, 7);
      expect(
        view.selected,
        isNull,
        reason: 'nothing selected yet, an empty tap does nothing',
      );

      view.tapCell(1, 1);
      expect(view.selected, mine);

      view.tapCell(1, 3);
      for (var i = 0; i < 10; i++) {
        network();
      }
      expect(
        host.storeOf<GridPosition>().get(mine)!.row,
        3,
        reason: 'the move order reached the host',
      );

      view.tapCell(4, 1);
      for (var i = 0; i < 20; i++) {
        network();
      }
      final hits = <AttackResolvedEvent>[];
      host.events.on<AttackResolvedEvent>(hits.add);
      for (var i = 0; i < 20; i++) {
        network();
      }
      final p = host.storeOf<GridPosition>().get(mine)!;
      expect(
        p.chebyshev(host.storeOf<GridPosition>().get(foe)!),
        lessThanOrEqualTo(1),
        reason: 'tapping an enemy walked the unit up to attack it',
      );
      await tester.pump();
    },
  );

  testWidgets('shows the disconnected view when the link closes', (
    tester,
  ) async {
    final host = _host();
    _unit(host, 'red', 0, 0);
    startTurnBasedGame(host, ['red', 'blue']);
    final hostSession = HostSession(world: host, teams: ['red', 'blue']);
    final link = LoopbackLink();
    hostSession.accept(link.a);
    var gone = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: OnlineStrategyView(
          endpoint: link.b,
          atlasRegistry: AtlasRegistry(),
          gridCols: 10,
          gridRows: 10,
          cellSize: 32,
          onDisconnected: () => gone++,
          disconnectedBuilder: (_) => const Text('bye', key: Key('bye')),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      host.step(0.05);
      hostSession.afterStep();
      link.advance();
    }
    link.b.close();
    await tester.pump();
    expect(find.byKey(const Key('bye')), findsOneWidget);
    expect(gone, 1);
  });
}
