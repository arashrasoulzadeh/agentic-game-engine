import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EngineView renders a world with a ScreenTint entity without error',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final tintEntity = world.spawn();
    world.storeOf<ScreenTint>().set(tintEntity, ScreenTint(0x80FF0000));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets('a fully transparent ScreenTint (alpha 0) renders without error too',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final tintEntity = world.spawn();
    world.storeOf<ScreenTint>().set(tintEntity, ScreenTint(0x00FF0000));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets('multiple ScreenTint entities all render without error', (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    world.storeOf<ScreenTint>().set(world.spawn(), ScreenTint(0x40FF0000));
    world.storeOf<ScreenTint>().set(world.spawn(), ScreenTint(0x400000FF));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });
}
