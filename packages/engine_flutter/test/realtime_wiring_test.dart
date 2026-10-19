import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity, Action;
import 'package:flutter_test/flutter_test.dart';

class _Scene extends Scene {
  late World world;
  @override
  Future<void> populate(
    World world,
    SceneController scenes,
    GameState state,
  ) async => this.world = world;
}

class _Game extends Game {
  _Game(this._config, this.scene);
  final GameConfig _config;
  final Scene scene;
  @override
  GameConfig get config => _config;
  @override
  Scene createInitialScene() => scene;
}

void main() {
  group('GameConfig.fixedTimestepSeconds', () {
    test(
      'defaults to null, is omitted from JSON, and round-trips when set',
      () {
        const none = GameConfig(worldWidth: 100, worldHeight: 100);
        expect(none.fixedTimestepSeconds, isNull);
        expect(none.toJson().containsKey('fixedTimestepSeconds'), isFalse);

        final back = GameConfig.fromJson(
          const GameConfig(
            worldWidth: 100,
            worldHeight: 100,
            fixedTimestepSeconds: 1 / 60,
          ).toJson(),
        );
        expect(back.fixedTimestepSeconds, closeTo(1 / 60, 1e-12));
      },
    );

    test('reads an integer from hand-written JSON', () {
      final c = GameConfig.fromJson({
        'worldWidth': 10,
        'worldHeight': 10,
        'fixedTimestepSeconds': 1,
      });
      expect(c.fixedTimestepSeconds, 1.0);
    });

    testWidgets(
      'GameRunner hands it to the EngineView, which then steps in fixed increments',
      (tester) async {
        final scene = _Scene();
        await tester.pumpWidget(
          MaterialApp(
            home: GameRunner(
              game: _Game(
                const GameConfig(
                  worldWidth: 100,
                  worldHeight: 100,
                  onScreenControls: OnScreenControlsMode.off,
                  fixedTimestepSeconds: 0.1,
                ),
                scene,
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(
          tester
              .widget<EngineView>(find.byType(EngineView))
              .fixedTimestepSeconds,
          0.1,
        );

        final dts = <double>[];
        scene.world.addSystem(_Recorder(dts));
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 70));
        }
        expect(dts, isNotEmpty);
        expect(
          dts.every((d) => d == 0.1),
          isTrue,
          reason: 'every step is exactly the configured dt',
        );
      },
    );
  });

  group('GridTapController with a local team (real-time)', () {
    World world() {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      return w;
    }

    test('selects and commands without a turn clock', () {
      final w = world();
      final mine = spawnRealtimeUnit(w, team: 'red', col: 1, row: 1);
      final foe = spawnRealtimeUnit(w, team: 'blue', col: 5, row: 5);
      final taps = GridTapController(32, localTeam: 'red');

      expect(taps.handleTap(w, const Offset(48, 48)), GridTapResult.selected);
      expect(
        taps.handleTap(w, const Offset(5.5 * 32, 5.5 * 32)),
        GridTapResult.commanded,
      );
      expect(
        (w.storeOf<OrderQueue>().get(mine)!.orders.single as AttackOrder)
            .target,
        foe,
      );
      expect(taps.handleDrag(w, const Offset(0, 0), const Offset(100, 100)), 1);
    });

    test('without a localTeam and without a clock, taps do nothing', () {
      final w = world();
      spawnRealtimeUnit(w, team: 'red', col: 1, row: 1);
      expect(
        GridTapController(32).handleTap(w, const Offset(48, 48)),
        GridTapResult.ignored,
      );
    });
  });
}

class _Recorder extends System {
  _Recorder(this.dts);
  final List<double> dts;
  @override
  String get name => 'recorder';
  @override
  void update(World world, double dt) => dts.add(dt);
}
