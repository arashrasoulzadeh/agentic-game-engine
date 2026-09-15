import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

/// Real, on-device diagnostics (`FrameStats`, this project's own
/// `adb logcat`-pulled DIAG lines -- see `TODO.md`'s "FPS drops while
/// the player is moving" history) found that a real fps-while-moving
/// drop traced to a Flutter widget-rebuild bug (`VirtualJoystick`
/// calling `setState` on every drag event), NOT to anything in
/// `EngineView`'s own step/paint/lighting pipeline. This benchmark
/// exists to keep proving that going forward, locally, without needing
/// a physical device: it runs the exact rendering ingredients a real
/// fps-while-moving report implicates (a shadow-casting player light,
/// walk-animation sprite-region churn, a panning camera, a populated
/// TileMap) standing still vs. actually moving, and reports whether
/// moving costs meaningfully more of `EngineView`'s own measured time.
///
/// Not a `benchmark_harness` script (those run via plain `dart run`,
/// but `EngineView`/`Canvas` need real Flutter bindings) -- uses the
/// same `flutter_test` + `Stopwatch`-via-`FrameStats` technique this
/// project has relied on throughout for render-focused benchmarking
/// (see this file's sibling `tile_collision_benchmark.dart`'s own
/// history in `TODO.md` for the same technique applied to tile
/// culling). Run with:
///   flutter test benchmark/render_pipeline_benchmark_test.dart --no-pub
///
/// Prints averaged `stepMs`/`paintMs`/`lightingMs` for both scenarios,
/// and asserts moving doesn't blow past a generous multiplier of
/// standing -- loose enough not to flake on CI hardware variance, but
/// tight enough to catch a real regression (e.g. a future change that
/// makes shadow raycasting re-run needlessly every frame regardless of
/// movement).
void main() {
  const frameCount = 120;
  const dt = Duration(milliseconds: 16);

  Future<FrameStats> runScenario(WidgetTester tester, {required bool moving}) async {
    final world = World(width: 4000, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);

    final mapEntity = world.spawn();
    world.storeOf<Position>().set(mapEntity, Position(0, 0));
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(
            cols: 200,
            rows: 20,
            tileWidth: 20,
            tileHeight: 20,
            tiles: [
              for (var row = 0; row < 20; row++)
                for (var col = 0; col < 200; col++) row == 19 ? 1 : 0,
            ],
            solidTileIds: {1},
          ),
        );

    final input = InputState();
    if (moving) input.pressedActions.add('right');

    final player = spawnPlayer(
      world,
      x: 100,
      y: 300,
      input: input,
      animations: MovementAnimationSet.fromSequences(
        idleRegion: 'idle',
        walkPrefix: 'walk',
        walkFrameCount: 4,
      ),
    );
    // Matches the real level's authored player light this session's
    // own investigation traced through -- castsShadows + a real ray
    // count, the single most expensive known per-frame lighting cost,
    // so this benchmark actually exercises it either way.
    world.storeOf<Light2D>().set(
        player, Light2D(radius: 150, castsShadows: true, shadowRayCount: 40));

    final behaviors = BehaviorRegistry();
    installPlatformerSystems(world, player: player, behaviors: behaviors);

    final registry = AtlasRegistry();
    final stats = FrameStats();

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: registry,
        camera: Camera(),
        cameraFollowEntity: player,
        ambientBrightness: 0.25,
        frameStats: stats,
      ),
    ));

    for (var i = 0; i < frameCount; i++) {
      await tester.pump(dt);
    }
    return stats;
  }

  testWidgets('standing vs. moving: step/paint/light costs, averaged over $frameCount frames',
      (tester) async {
    final standing = await runScenario(tester, moving: false);
    final moving = await runScenario(tester, moving: true);

    // ignore: avoid_print
    print('standing: step=${standing.stepMs.toStringAsFixed(3)}ms '
        'paint=${standing.paintMs.toStringAsFixed(3)}ms '
        'light=${standing.lightingMs.toStringAsFixed(3)}ms');
    // ignore: avoid_print
    print('moving:   step=${moving.stepMs.toStringAsFixed(3)}ms '
        'paint=${moving.paintMs.toStringAsFixed(3)}ms '
        'light=${moving.lightingMs.toStringAsFixed(3)}ms');

    // Generous multiplier (not near-equality) -- this is a real
    // Stopwatch measurement on shared CI/dev hardware, not a
    // deterministic count, so some noise is expected; the point is
    // catching an order-of-magnitude regression, not micro-tuning.
    expect(moving.stepMs, lessThan(standing.stepMs * 5 + 1),
        reason: 'moving should not make world.step() meaningfully more expensive -- '
            'if it does, something in the platformer/AI pipeline is doing extra work '
            'only while the player moves');
    expect(moving.paintMs, lessThan(standing.paintMs * 5 + 1),
        reason: 'moving should not make the paint pass meaningfully more expensive -- '
            'if it does, walk-animation sprite-region churn or camera panning is '
            'costing more than Canvas.drawAtlas batching/viewport culling should allow');
    expect(moving.lightingMs, lessThan(standing.lightingMs * 5 + 1),
        reason: "moving should not make the player's own shadow-casting light more "
            'expensive -- it re-runs its raycastTileMap sweep every frame either way '
            '(no cacheShadowGeometry set here), so standing and moving should already '
            'cost about the same');
  });
}
