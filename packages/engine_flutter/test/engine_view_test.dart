import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/services.dart';
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

  testWidgets('showFpsOverlay renders an fps readout and recomputes over many ticks',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
        showFpsOverlay: true,
      ),
    ));

    // >30 ticks so the rolling _recentDts window actually evicts its
    // oldest entry (the branch that keeps it capped at 30).
    for (var i = 0; i < 35; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final text = tester.widget<Text>(find.textContaining('fps:')).data!;
    expect(text, contains('fps:'));
    expect(text, contains('tick:'));
    expect(text, contains('entities:'));
    expect(text, contains('sprites:'));
    expect(text, contains('particles:'));
  });

  testWidgets('cameraFollowEntity moves the camera toward that entity\'s Position',
      (tester) async {
    final world = World(width: 2000, height: 2000);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final player = world.spawn();
    world.storeOf<Position>().set(player, Position(1000, 1000));
    final camera = Camera(x: 0, y: 0);

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: camera,
        cameraFollowEntity: player,
      ),
    ));

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    expect(camera.x, greaterThan(0));
  });

  testWidgets('a keyboard-bound InputController receives key events through EngineView',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    final controller = InputController();

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
        inputController: controller,
      ),
    ));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.state.isPressed('left'), isTrue);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.state.isPressed('left'), isFalse);
  });

  testWidgets('onWorldTap receives the tap position converted to world coordinates',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    final camera = Camera(x: 0, y: 0, zoom: 1);
    Offset? tapped;

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: camera,
        onWorldTap: (worldPosition) => tapped = worldPosition,
      ),
    ));
    await tester.pump();

    // The test surface is 800x600 by default, so its center (400,300)
    // sits over world origin (0,0) when the camera is centered there.
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();

    expect(tapped, isNotNull);
    expect(tapped!.dx, closeTo(0, 0.01));
    expect(tapped!.dy, closeTo(0, 0.01));
  });

  testWidgets('with no onWorldTap, a tap is a no-op rather than throwing',
      (tester) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: AtlasRegistry(),
        camera: Camera(),
      ),
    ));
    await tester.pump();

    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
  });
}
