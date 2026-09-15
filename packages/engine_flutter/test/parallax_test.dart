import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 8, 8),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(8, 8);
}

Future<Color> _pixelAt(WidgetTester tester, Key boundaryKey, Offset point) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
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
  test('ParallaxLayer round-trips through toJson/fromJson with defaults', () {
    final layer = ParallaxLayer('bg', 'sky');
    final decoded = ParallaxLayer.fromJson(layer.toJson());

    expect(decoded.atlasId, 'bg');
    expect(decoded.region, 'sky');
    expect(decoded.scrollFactorX, 0.5);
    expect(decoded.scrollFactorY, 0);
    expect(decoded.tileX, isTrue);
    expect(decoded.tileY, isFalse);
  });

  test('ParallaxLayer.fromJson honors explicit non-default values', () {
    final layer = ParallaxLayer(
      'bg',
      'mountains',
      scrollFactorX: 0.2,
      scrollFactorY: 0.1,
      tileX: false,
      tileY: true,
    );
    final decoded = ParallaxLayer.fromJson(layer.toJson());

    expect(decoded.scrollFactorX, 0.2);
    expect(decoded.scrollFactorY, 0.1);
    expect(decoded.tileX, isFalse);
    expect(decoded.tileY, isTrue);
  });

  test('ParallaxLayer.fitHeight defaults to false and round-trips through toJson/fromJson', () {
    expect(ParallaxLayer('bg', 'sky').fitHeight, isFalse);

    final layer = ParallaxLayer('bg', 'sky', fitHeight: true);
    final decoded = ParallaxLayer.fromJson(layer.toJson());
    expect(decoded.fitHeight, isTrue);
  });

  testWidgets(
      'fitHeight stretches a single draw to cover the full viewport height -- '
      'without it, a short image (native size, not tiled) leaves the top of a '
      'taller viewport uncovered, showing the background color instead',
      (tester) async {
    final registry = AtlasRegistry();
    registry.register('bg', SpriteAtlas(await _tinyImage(), {
      'sky': const Rect.fromLTWH(0, 0, 8, 8),
    }));

    Future<Color> topLeftPixelFor(bool fitHeight) async {
      final world = World(width: 2000, height: 400);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<ParallaxLayer>().set(
            entity,
            ParallaxLayer('bg', 'sky', tileY: false, fitHeight: fitHeight),
          );

      final boundaryKey = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300, // much taller than the 8px source image
            child: RepaintBoundary(
              key: boundaryKey,
              child: EngineView(
                world: world,
                atlasRegistry: registry,
                camera: Camera(),
                backgroundColor: const Color(0xFF000000),
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      return (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(5, 5))))!;
    }

    final withoutFitHeight = await topLeftPixelFor(false);
    expect(withoutFitHeight.r, 0,
        reason: 'the 8px-tall white image, drawn at native size and '
            'vertically centered, does not reach the top-left corner of a '
            '300px-tall viewport -- still the black backgroundColor, not '
            'the white sprite -- confirms the bug this feature fixes '
            'actually reproduces without it');

    final withFitHeight = await topLeftPixelFor(true);
    expect(withFitHeight.r, greaterThan(0),
        reason: 'fitHeight stretches the same image to cover the full '
            'viewport height, so the top-left corner now shows the white '
            'sprite instead of the black backgroundColor');
  });

  testWidgets('EngineView renders a tiled parallax layer without error', (tester) async {
    final world = World(width: 2000, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final registry = AtlasRegistry();
    registry.register('bg', SpriteAtlas(await _tinyImage(), {
      'sky': const Rect.fromLTWH(0, 0, 8, 8),
    }));

    final entity = world.spawn();
    world.storeOf<Position>().set(entity, Position(0, 0));
    world.storeOf<ParallaxLayer>().set(entity, ParallaxLayer('bg', 'sky'));

    await tester.pumpWidget(MaterialApp(
      home: EngineView(
        world: world,
        atlasRegistry: registry,
        camera: Camera(x: 500, y: 0),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(EngineView), findsOneWidget);
  });

  testWidgets('a parallax layer referencing an unregistered atlas is skipped, not a crash',
      (tester) async {
    final world = World(width: 2000, height: 400);
    registerCoreComponents(world);
    registerFlutterComponents(world);

    final entity = world.spawn();
    world.storeOf<Position>().set(entity, Position(0, 0));
    world.storeOf<ParallaxLayer>().set(entity, ParallaxLayer('missing', 'sky'));

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
}
