import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fixedTimestepSeconds null (default) steps once per rendered frame with the real dt',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
    ));

    await tester.pump(const Duration(milliseconds: 16)); // baseline only
    await tester.pump(const Duration(milliseconds: 100));
    expect(world.tick, 1, reason: 'one world.step per rendered frame, unchanged from before');
  });

  testWidgets('fixedTimestepSeconds steps world.step exactly once per whole accumulated step',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
        fixedTimestepSeconds: 0.1,
      ),
    ));

    await tester.pump(const Duration(milliseconds: 16)); // baseline only, no dt yet
    await tester.pump(const Duration(milliseconds: 200)); // exactly 2 whole 0.1s steps
    expect(world.tick, 2);

    await tester.pump(const Duration(milliseconds: 50)); // half a step -- accumulator only
    expect(world.tick, 2, reason: 'a partial step must not advance world.tick yet');

    await tester.pump(const Duration(milliseconds: 50)); // completes the accumulated step
    expect(world.tick, 3);
  });

  testWidgets('fixedTimestepSeconds caps steps-per-frame instead of spiraling on a big backlog',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
        fixedTimestepSeconds: 0.01, // 100Hz
      ),
    ));

    await tester.pump(const Duration(milliseconds: 16)); // baseline only
    // 200ms / 10ms-per-step = 20 potential steps -- capped at 5 per
    // rendered frame, with the rest of the backlog dropped rather than
    // carried over (see EngineView.fixedTimestepSeconds's doc comment
    // on why: never clamping is the classic "spiral of death").
    await tester.pump(const Duration(milliseconds: 200));
    expect(world.tick, 5);
  });

  testWidgets('a moving sprite still renders without crashing under fixed-timestep interpolation',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(MovementSystem());

    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(50, 50));
    world.storeOf<Velocity>().set(id, Velocity(100, 0));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
        fixedTimestepSeconds: 1 / 60,
      ),
    ));

    await tester.pump(const Duration(milliseconds: 16));
    // A handful of frames each shorter than one fixed step at some
    // points and longer at others, to exercise both "mid-accumulation,
    // interpolating between two past states" and "just landed exactly
    // on a step boundary" paths.
    for (final ms in [5, 20, 8, 30, 16]) {
      await tester.pump(Duration(milliseconds: ms));
    }

    expect(find.byType(EngineView), findsOneWidget);
    expect(world.storeOf<Position>().get(id)!.x, greaterThan(50));
  });
}
