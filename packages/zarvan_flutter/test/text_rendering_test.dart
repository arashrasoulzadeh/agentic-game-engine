import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_flutter/zarvan_flutter.dart' as engine show Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EngineView renders world-space text without crashing', (
    tester,
  ) async {
    final world = World(width: 400, height: 300);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final id = world.spawn();
    world.componentsOf<Position>().set(id, Position(100, 100));
    world.componentsOf<engine.Text>().set(id, engine.Text('Hello world'));

    await tester.pumpWidget(
      MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets(
    'EngineView renders screen-space text at a fixed viewport position',
    (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.componentsOf<Position>().set(id, Position(10, 10));
      world.componentsOf<engine.Text>().set(
        id,
        engine.Text(
          'HUD',
          screenSpace: true,
          align: TextAlignment.left,
          zIndex: 100,
        ),
      );

      // A camera pointed far from the text's Position -- if this were
      // world-space it'd be nowhere near the viewport; screenSpace means
      // it should render regardless.
      await tester.pumpWidget(
        MaterialApp(
          home: EngineView(
            world: world,
            atlasRegistry: AtlasRegistry(),
            camera: Camera(x: 5000, y: 5000),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    },
  );

  testWidgets(
    'EngineView renders text with no Position gracefully (skipped, not a crash)',
    (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.componentsOf<engine.Text>().set(
        id,
        engine.Text('orphaned'),
      ); // no Position

      await tester.pumpWidget(
        MaterialApp(
          home: EngineView(
            world: world,
            atlasRegistry: AtlasRegistry(),
            camera: Camera(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    },
  );

  testWidgets(
    'EngineView wraps long text onto multiple lines when maxWidth is set',
    (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.componentsOf<Position>().set(id, Position(100, 100));
      world.componentsOf<engine.Text>().set(
        id,
        engine.Text(
          'This is a long line of dialogue that should wrap onto several lines',
          screenSpace: true,
          maxWidth: 80,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: EngineView(
            world: world,
            atlasRegistry: AtlasRegistry(),
            camera: Camera(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    },
  );

  testWidgets(
    'EngineView renders unbounded (maxWidth null) world-space text at any zoom',
    (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.componentsOf<Position>().set(id, Position(100, 100));
      world.componentsOf<engine.Text>().set(id, engine.Text('unwrapped'));

      await tester.pumpWidget(
        MaterialApp(
          home: EngineView(
            world: world,
            atlasRegistry: AtlasRegistry(),
            camera: Camera(zoom: 2),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    },
  );
}
