import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EngineView renders and steps the world without error',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(MovementSystem());

    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(50, 50));
    world.storeOf<Velocity>().set(id, Velocity(10, 0));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
      ),
    ));

    expect(world.tick, 0);
    // The ticker's first callback only establishes a baseline elapsed time
    // (dt can't be computed with no prior tick), so a second pump is
    // needed before world.step actually runs.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(EngineView), findsOneWidget);
    expect(world.tick, greaterThan(0));
  });
}
