import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 16, 16),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(16, 16);
}

void main() {
  group('NineSliceSprite', () {
    test('round-trips through toJson/fromJson', () {
      final sprite = NineSliceSprite(
        'panel',
        'bg',
        width: 200,
        height: 100,
        insetLeft: 8,
        insetTop: 8,
        insetRight: 8,
        insetBottom: 8,
        zIndex: 4,
      );
      final restored = NineSliceSprite.fromJson(sprite.toJson());

      expect(restored.atlasId, 'panel');
      expect(restored.region, 'bg');
      expect(restored.width, 200);
      expect(restored.height, 100);
      expect(restored.insetLeft, 8);
      expect(restored.insetTop, 8);
      expect(restored.insetRight, 8);
      expect(restored.insetBottom, 8);
      expect(restored.zIndex, 4);
    });

    test('fromJson defaults zIndex to 0 when absent', () {
      final restored = NineSliceSprite.fromJson({
        'atlasId': 'panel',
        'region': 'bg',
        'width': 100,
        'height': 50,
        'insetLeft': 4,
        'insetTop': 4,
        'insetRight': 4,
        'insetBottom': 4,
      });
      expect(restored.zIndex, 0);
    });
  });

  group('EngineView NineSliceSprite rendering', () {
    testWidgets('renders a nine-slice panel without crashing', (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('panel', SpriteAtlas(await _tinyImage(), {
        'bg': const Rect.fromLTWH(0, 0, 16, 16),
      }));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(10, 10));
      world.storeOf<NineSliceSprite>().set(
            id,
            NineSliceSprite(
              'panel',
              'bg',
              width: 200,
              height: 120,
              insetLeft: 4,
              insetTop: 4,
              insetRight: 4,
              insetBottom: 4,
            ),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('skips a destination cell that would be zero/negative size instead of crashing',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('panel', SpriteAtlas(await _tinyImage(), {
        'bg': const Rect.fromLTWH(0, 0, 16, 16),
      }));

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(10, 10));
      // width/height smaller than insetLeft+insetRight/insetTop+insetBottom
      // -- the center/opposite-edge cells would come out negative size.
      world.storeOf<NineSliceSprite>().set(
            id,
            NineSliceSprite(
              'panel',
              'bg',
              width: 4,
              height: 4,
              insetLeft: 8,
              insetTop: 8,
              insetRight: 8,
              insetBottom: 8,
            ),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('renders gracefully (skipped) when the atlas is not registered',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(10, 10));
      world.storeOf<NineSliceSprite>().set(
            id,
            NineSliceSprite(
              'missing',
              'bg',
              width: 100,
              height: 50,
              insetLeft: 4,
              insetTop: 4,
              insetRight: 4,
              insetBottom: 4,
            ),
          );

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: AtlasRegistry(), camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });

    testWidgets('renders gracefully (skipped) when there is no Position',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final registry = AtlasRegistry();
      registry.register('panel', SpriteAtlas(await _tinyImage(), {
        'bg': const Rect.fromLTWH(0, 0, 16, 16),
      }));

      final id = world.spawn();
      world.storeOf<NineSliceSprite>().set(
            id,
            NineSliceSprite(
              'panel',
              'bg',
              width: 100,
              height: 50,
              insetLeft: 4,
              insetTop: 4,
              insetRight: 4,
              insetBottom: 4,
            ),
          ); // no Position

      await tester.pumpWidget(MaterialApp(
        home: EngineView(world: world, atlasRegistry: registry, camera: Camera()),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(EngineView), findsOneWidget);
    });
  });
}
