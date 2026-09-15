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
    {double? ambientBrightness, Color? backgroundColor}) async {
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
            backgroundColor: backgroundColor ?? const Color(0xFF000000),
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

    testWidgets(
        'ambientBrightness composes with (scales) dayNightCycle instead of being '
        'silently overridden by it -- regression test: a scene-tuned ambientBrightness '
        "(e.g. 0.25, chosen so the scene's own Light2D lights read correctly) must "
        'remain a real ceiling the cycle can only dim further, not get discarded the '
        'moment a dayNightCycle exists', (tester) async {
      // Deep night (dayNightCycle.ambientBrightness ~0.18) must darken
      // FURTHER than the 0.25 baseline, not simply replace it with 0.18
      // outright. A white background makes the direction unambiguous
      // (black would already read as "fully dark" either way): total
      // luminance must drop, not just land near wherever 0.18 alone
      // would put it.
      final baselineOnWhite = await _renderAmbientPixel(tester, null,
          ambientBrightness: 0.25, backgroundColor: const Color(0xFFFFFFFF));
      final nightOnWhite = await _renderAmbientPixel(
        tester,
        DayNightCycle(hour: 2),
        ambientBrightness: 0.25,
        backgroundColor: const Color(0xFFFFFFFF),
      );
      final baselineLuma = baselineOnWhite.r + baselineOnWhite.g + baselineOnWhite.b;
      final nightLuma = nightOnWhite.r + nightOnWhite.g + nightOnWhite.b;
      expect(nightLuma, lessThan(baselineLuma),
          reason: 'combined brightness (0.25 * ~0.18 =~ 0.045) must read darker than '
              "the 0.25 baseline alone -- if dayNightCycle silently overrides "
              'ambientBrightness instead of scaling it, night (~0.18) would actually '
              'read BRIGHTER than the tuned 0.25 baseline, the exact regression this '
              'test catches');
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

    testWidgets(
        "a shadow-casting light's revealed area reads brighter than the unrevealed "
        'ambient around it -- regression test for a real on-screen report ("user '
        'light darkens the GI") traced to DayNightCycle.ambientColorArgb/'
        '_effectiveAmbientColorArgb returning a tint still bright enough, at the high '
        'alpha dusk/night already has, to outshine an area a light had genuinely '
        'revealed back to the true (but comparatively dim) scene colors',
        (tester) async {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      // Open sky above a ground row -- same shape as test_game's prison
      // level, whose player light (radius 220, castsShadows, 40 rays,
      // blockOneWayPlatforms) this mirrors exactly.
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(
            mapEntity,
            TileMap(
              cols: 40,
              rows: 30,
              tileWidth: 20,
              tileHeight: 20,
              tiles: [
                for (var row = 0; row < 30; row++)
                  for (var col = 0; col < 40; col++) row == 28 ? 1 : 0,
              ],
              solidTileIds: {1},
            ),
          );

      final player = world.spawn();
      world.storeOf<Position>().set(player, Position(300, 500));
      world.storeOf<Light2D>().set(
          player,
          Light2D(
            radius: 220,
            intensity: 1,
            castsShadows: true,
            shadowRayCount: 40,
            blockOneWayPlatforms: true,
            shadowEdgeSoftness: 12,
          ));

      final boundaryKey = UniqueKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: RepaintBoundary(
              key: boundaryKey,
              child: EngineView(
                world: world,
                atlasRegistry: AtlasRegistry(),
                camera: Camera(x: 300, y: 300),
                backgroundColor: const Color(0xFF807060),
                ambientBrightness: 0.25,
                dayNightCycle: DayNightCycle(hour: 19), // dusk
              ),
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      // Camera centered at world (300,300) on an 800x600 viewport ->
      // screen = world - (300,300) + (400,300). Directly above the
      // player, well inside the 220 radius, open sky, unobstructed --
      // should be the most-revealed point on screen. Far corner sits
      // outside the light's radius entirely -- should stay at the
      // plain (unrevealed) ambient wash.
      final revealed = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(400, 350))))!;
      final unrevealed = (await tester.runAsync(
          () => _pixelAt(tester, boundaryKey, const Offset(50, 50))))!;

      expect(revealed.r, greaterThan(unrevealed.r));
      expect(revealed.g, greaterThan(unrevealed.g));
      expect(revealed.b, greaterThan(unrevealed.b));
    });
  });
}
