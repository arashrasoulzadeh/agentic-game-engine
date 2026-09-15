import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

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

Future<Color> _renderAmbientPixel(WidgetTester tester, DayNightCycle? cycle,
    {double? ambientBrightness}) async {
  final world = World(width: 400, height: 300);
  registerCoreComponents(world);
  registerFlutterComponents(world);

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
            atlasRegistry: AtlasRegistry(),
            camera: Camera(),
            ambientBrightness: ambientBrightness ?? 1.0,
            dayNightCycle: cycle,
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 16));

  // No lights, so the whole viewport is one flat ambient-wash color --
  // any point works; the corner avoids any future off-by-one edge cases.
  return (await tester.runAsync(() => _pixelAt(tester, boundaryKey, const Offset(10, 10))))!;
}

void main() {
  group('EngineView.dayNightCycle', () {
    // EngineView always paints an opaque backgroundColor (black by
    // default) first, then composites the ambient wash on top via
    // saveLayer -- so the final pixel is always fully opaque (a == 1)
    // regardless of ambientBrightness; what actually changes is the RGB
    // mix, since the wash blends its own color over that black base.

    testWidgets('with no cycle, ambientBrightness 0 still produces a plain black wash',
        (tester) async {
      final pixel = await _renderAmbientPixel(tester, null, ambientBrightness: 0.0);
      expect(pixel.r, 0);
      expect(pixel.g, 0);
      expect(pixel.b, 0);
    });

    testWidgets('a bright midday cycle renders with no visible darkness wash', (tester) async {
      final pixel = await _renderAmbientPixel(tester, DayNightCycle(hour: 12));
      // ambientBrightness 1.0 -> overlay alpha 0 -> the opaque black
      // background shows through completely untouched either way.
      expect(pixel.r, 0);
      expect(pixel.g, 0);
      expect(pixel.b, 0);
    });

    testWidgets('a deep-night cycle washes the scene with its dark blue tint, not plain black',
        (tester) async {
      final pixel = await _renderAmbientPixel(tester, DayNightCycle(hour: 2));
      expect(pixel.b, greaterThan(0), reason: 'night is dim but not zero-brightness, so the '
          'blue-tinted wash should show through over the black background');
      expect(pixel.b, greaterThan(pixel.r),
          reason: 'DayNightCycle.ambientColorArgb at night is blue-leaning, unlike the plain '
              'black wash ambientBrightness alone produces');
    });

    testWidgets('a dawn cycle washes the scene with a warm orange tint', (tester) async {
      final pixel = await _renderAmbientPixel(tester, DayNightCycle(hour: 6.5));
      expect(pixel.r, greaterThan(0));
      expect(pixel.r, greaterThan(pixel.b), reason: 'dawn tint is warm (red/orange dominant)');
    });

    testWidgets('heavy rain further dims and cools the tint versus clear weather at the '
        'same hour', (tester) async {
      final clear = await _renderAmbientPixel(
        tester,
        DayNightCycle(hour: 12, weather: Weather.clear),
      );
      final rain = await _renderAmbientPixel(
        tester,
        DayNightCycle(hour: 12, weather: Weather.rain, weatherIntensity: 1),
      );
      // Clear midday has ambientBrightness 1.0 -> no wash at all -> pure
      // black background. Rain dims midday below 1.0, so its blue-grey
      // wash actually shows through as a visible non-black color.
      expect(clear.r + clear.g + clear.b, 0);
      expect(rain.r + rain.g + rain.b, greaterThan(0));
    });

    testWidgets('advances hour every tick, the same way Camera.update already does',
        (tester) async {
      final world = World(width: 400, height: 300);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final cycle = DayNightCycle(hour: 0, dayLengthSeconds: 0.048);
      await tester.pumpWidget(MaterialApp(
        home: EngineView(
          world: world,
          atlasRegistry: AtlasRegistry(),
          camera: Camera(),
          dayNightCycle: cycle,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));

      // Two 16ms ticks against a 48ms "day" -> a real, visible advance
      // rather than exactly checking a fragile floating-point value.
      expect(cycle.hour, greaterThan(0));
    });
  });
}
