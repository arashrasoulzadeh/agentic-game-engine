import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_strategy/engine_strategy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the strategy template's skirmish level with its placeholder atlases and (with
/// `UPDATE_SCREENSHOTS=1`) writes the PNG the docs use to `docs/img/`. The template draws plain coloured
/// squares for units and terrain, so no art is needed. Without the variable it only checks the level
/// renders, so the docs image is regenerated on purpose rather than churning on every run.
const _levelPath =
    '../engine_cli/templates/strategy_game/assets/levels/skirmish.level.json';

Future<SpriteAtlas> _atlas(
  Map<String, Color> colors, {
  double size = 32,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final regions = <String, Rect>{};
  var i = 0;
  for (final entry in colors.entries) {
    final rect = Rect.fromLTWH(i * size, 0, size, size);
    canvas.drawRect(rect, Paint()..color = entry.value);
    regions[entry.key] = rect;
    i++;
  }
  final image = await recorder.endRecording().toImage(
    (size * colors.length).toInt(),
    size.toInt(),
  );
  return SpriteAtlas(image, regions);
}

void main() {
  testWidgets('strategy skirmish screenshot', (tester) async {
    tester.view.physicalSize = const Size(768, 768);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final level =
        jsonDecode(File(_levelPath).readAsStringSync()) as Map<String, dynamic>;
    final world = World(width: 384, height: 384);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    Level.loadInto(world, level);
    final map = world.componentsOf<TileMap>().denseAt(0);
    installStrategySystems(
      world,
      navigator: GridNavigator.fromTileMap(map, terrainCosts: {2: 3}),
      cellSize: 48,
      moveHighlight: (atlasId: 'terrain', region: 'highlight'),
    );
    startTurnBasedGame(world, ['red', 'blue']);

    final registry = AtlasRegistry()
      ..register(
        'units',
        await tester.runAsync(
              () => _atlas({
                'red': Colors.redAccent,
                'blue': Colors.lightBlueAccent,
              }),
            )
            as SpriteAtlas,
      )
      ..register(
        'terrain',
        await tester.runAsync(
              () => _atlas({
                'grass': const Color(0xFF3B6B3A),
                'forest': const Color(0xFF1F4A2A),
                'mountain': const Color(0xFF6E6E78),
                'highlight': const Color(0x6640E0D0),
              }),
            )
            as SpriteAtlas,
      );

    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: EngineView(
            world: world,
            atlasRegistry: registry,
            camera: Camera(x: 192, y: 192),
            stepsWorld: false,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final png = await tester.runAsync(() async {
      final ro = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundary),
      );
      final image = await ro.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    expect(png!.length, greaterThan(1000));

    if (Platform.environment['UPDATE_SCREENSHOTS'] == '1') {
      File('../../docs/img/strategy-skirmish.png').writeAsBytesSync(png);
    }
  });
}
