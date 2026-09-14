import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage(Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = color);
  return recorder.endRecording().toImage(4, 4);
}

Future<Color> _pixelAt(WidgetTester tester, Key boundaryKey, Offset point) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  final image = await boundary.toImage();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final x = point.dx.round().clamp(0, image.width - 1);
  final y = point.dy.round().clamp(0, image.height - 1);
  final offset = (y * image.width + x) * 4;
  final data = bytes!;
  return Color.fromARGB(
    data.getUint8(offset + 3),
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
}

void main() {
  group('ClipShape', () {
    test('defaults: circle, radius 100, reveal mode, no softness', () {
      final shape = ClipShape();
      expect(shape.isCircle, isTrue);
      expect(shape.radius, 100);
      expect(shape.width, 200);
      expect(shape.height, 200);
      expect(shape.mode, ClipShapeMode.reveal);
      expect(shape.softness, 0);
    });

    test('round-trips through toJson/fromJson', () {
      final shape = ClipShape(
        isCircle: false,
        radius: 50,
        width: 120,
        height: 80,
        mode: ClipShapeMode.cutout,
        softness: 6,
      );
      final restored = ClipShape.fromJson(shape.toJson());

      expect(restored.isCircle, isFalse);
      expect(restored.radius, 50);
      expect(restored.width, 120);
      expect(restored.height, 80);
      expect(restored.mode, ClipShapeMode.cutout);
      expect(restored.softness, 6);
    });

    test('fromJson defaults match the constructor defaults', () {
      final restored = ClipShape.fromJson({});
      expect(restored.isCircle, isTrue);
      expect(restored.radius, 100);
      expect(restored.width, 200);
      expect(restored.height, 200);
      expect(restored.mode, ClipShapeMode.reveal);
      expect(restored.softness, 0);
    });

    test('fromJson falls back to reveal for an unknown/missing mode string', () {
      final restored = ClipShape.fromJson({'mode': 'nonsense'});
      expect(restored.mode, ClipShapeMode.reveal);
    });
  });

  group('EngineView ClipShape rendering', () {
    testWidgets(
        'reveal mode clips the scene to the shape -- content outside a reveal circle is '
        'not drawn, content inside it is', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFFFFFF)), {
        'inside': const Rect.fromLTWH(0, 0, 4, 4),
        'outside': const Rect.fromLTWH(0, 0, 4, 4),
      }));

      // World (0,0) -> screen (200,150); world (150,0) -> screen (350,150)
      // on a 400x300 viewport at Camera() default (x:0,y:0,zoom:1).
      final insideEntity = world.spawn();
      world.storeOf<Position>().set(insideEntity, Position(0, 0));
      world.storeOf<Sprite>().set(
          insideEntity, Sprite('atlas', 'inside', zIndex: 0, scaleX: 20, scaleY: 20));

      final outsideEntity = world.spawn();
      world.storeOf<Position>().set(outsideEntity, Position(150, 0));
      world.storeOf<Sprite>().set(
          outsideEntity, Sprite('atlas', 'outside', zIndex: 0, scaleX: 20, scaleY: 20));

      final clipEntity = world.spawn();
      world.storeOf<Position>().set(clipEntity, Position(0, 0));
      world.storeOf<ClipShape>().set(
          clipEntity, ClipShape(radius: 40, mode: ClipShapeMode.reveal));

      final boundaryKey = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: boundaryKey,
              child: EngineView(
                world: world,
                atlasRegistry: registry,
                camera: Camera(),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      final insidePixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(200, 150))))!;
      final outsidePixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(350, 150))))!;

      expect(insidePixel.a, greaterThan(0.5),
          reason: 'the reveal circle covers world (0,0), so the sprite there is drawn');
      expect(outsidePixel.a, lessThan(0.1),
          reason: 'world (150,0) sits well outside the 40px reveal radius, so the '
              'sprite there is clipped away entirely, not just darkened');
    });

    testWidgets(
        'cutout mode erases already-drawn content under the shape, leaving content '
        'elsewhere untouched', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('atlas', SpriteAtlas(await _tinyImage(const Color(0xFFFFFFFF)), {
        'covered': const Rect.fromLTWH(0, 0, 4, 4),
        'clear': const Rect.fromLTWH(0, 0, 4, 4),
      }));

      final coveredEntity = world.spawn();
      world.storeOf<Position>().set(coveredEntity, Position(0, 0));
      world.storeOf<Sprite>().set(
          coveredEntity, Sprite('atlas', 'covered', zIndex: 0, scaleX: 20, scaleY: 20));

      final clearEntity = world.spawn();
      world.storeOf<Position>().set(clearEntity, Position(150, 0));
      world.storeOf<Sprite>().set(
          clearEntity, Sprite('atlas', 'clear', zIndex: 0, scaleX: 20, scaleY: 20));

      final clipEntity = world.spawn();
      world.storeOf<Position>().set(clipEntity, Position(0, 0));
      world.storeOf<ClipShape>().set(
          clipEntity, ClipShape(radius: 40, mode: ClipShapeMode.cutout));

      final boundaryKey = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: RepaintBoundary(
              key: boundaryKey,
              child: EngineView(
                world: world,
                atlasRegistry: registry,
                camera: Camera(),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      final coveredPixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(200, 150))))!;
      final clearPixel = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(350, 150))))!;

      expect(coveredPixel.a, lessThan(0.1),
          reason: 'the cutout circle covers world (0,0), erasing the sprite drawn there');
      expect(clearPixel.a, greaterThan(0.5),
          reason: 'world (150,0) is outside the cutout, so its sprite survives untouched');
    });

    testWidgets('reveal and cutout shapes can coexist without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final revealEntity = world.spawn();
      world.storeOf<Position>().set(revealEntity, Position(100, 100));
      world.storeOf<ClipShape>().set(
          revealEntity, ClipShape(radius: 150, mode: ClipShapeMode.reveal));

      final cutoutEntity = world.spawn();
      world.storeOf<Position>().set(cutoutEntity, Position(100, 100));
      world.storeOf<ClipShape>().set(
          cutoutEntity, ClipShape(radius: 30, mode: ClipShapeMode.cutout, softness: 4));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('a rectangular ClipShape renders without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final clipEntity = world.spawn();
      world.storeOf<Position>().set(clipEntity, Position(100, 100));
      world.storeOf<ClipShape>().set(
          clipEntity, ClipShape(isCircle: false, width: 120, height: 60));

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('a ClipShape with no Position is skipped gracefully, not a crash',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<ClipShape>().set(id, ClipShape()); // no Position

      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('no ClipShape present renders identically to the unclipped path (no crash)',
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
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });
  });
}
