import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

ViewportLayout _layout(
  ViewportFit fit,
  ui.Size screen, {
  double ratio = 2.0,
  bool center = true,
  ui.RRect? safe,
}) => ViewportManager(
  ViewportConfig(targetAspectRatio: ratio, fit: fit, centerViewport: center),
).computeLayout(screen, safe);

void main() {
  group('ViewportManager.computeLayout', () {
    test(
      'a screen already at the target ratio is filled exactly, with no bars',
      () {
        for (final fit in ViewportFit.values) {
          final l = _layout(fit, const ui.Size(800, 400));
          expect(
            l.contentRect,
            const ui.Rect.fromLTWH(0, 0, 800, 400),
            reason: '$fit',
          );
          expect(l.isLetterboxed, isFalse);
          expect(l.isPillarboxed, isFalse);
        }
      },
    );

    test('contain on a wider screen pillarboxes: full height, centred', () {
      final l = _layout(ViewportFit.contain, const ui.Size(1200, 400));
      expect(l.contentRect, const ui.Rect.fromLTWH(200, 0, 800, 400));
      expect((l.isLetterboxed, l.isPillarboxed), (false, true));
    });

    test('contain on a taller screen letterboxes: full width, centred', () {
      final l = _layout(ViewportFit.contain, const ui.Size(400, 600));
      expect(l.contentRect, const ui.Rect.fromLTWH(0, 200, 400, 200));
      expect((l.isLetterboxed, l.isPillarboxed), (true, false));
    });

    test('cover fills the screen and overflows the other way (cropped)', () {
      final wide = _layout(ViewportFit.cover, const ui.Size(1200, 400));
      expect(wide.contentRect, const ui.Rect.fromLTWH(0, -100, 1200, 600));
      expect((wide.isLetterboxed, wide.isPillarboxed), (false, false));

      final tall = _layout(ViewportFit.cover, const ui.Size(400, 600));
      expect(tall.contentRect, const ui.Rect.fromLTWH(-400, 0, 1200, 600));
    });

    test('width always spans the width; height always spans the height', () {
      final w = _layout(ViewportFit.width, const ui.Size(400, 600));
      expect(w.contentRect, const ui.Rect.fromLTWH(0, 200, 400, 200));
      final wShort = _layout(ViewportFit.width, const ui.Size(400, 100));
      expect(
        wShort.contentRect,
        const ui.Rect.fromLTWH(0, -50, 400, 200),
        reason: 'cropped vertically',
      );

      final h = _layout(ViewportFit.height, const ui.Size(1200, 400));
      expect(h.contentRect, const ui.Rect.fromLTWH(200, 0, 800, 400));
      final hNarrow = _layout(ViewportFit.height, const ui.Size(300, 400));
      expect(
        hNarrow.contentRect,
        const ui.Rect.fromLTWH(-250, 0, 800, 400),
        reason: 'cropped at the sides',
      );
    });

    test('centerViewport: false pins the area to the top left', () {
      final l = _layout(
        ViewportFit.contain,
        const ui.Size(1200, 400),
        center: false,
      );
      expect(l.contentRect.topLeft, ui.Offset.zero);
    });

    test(
      'the safe area shrinks the available space and offsets the result',
      () {
        final safe = ui.RRect.fromLTRBAndCorners(
          0,
          40,
          800,
          440,
        ); // 800x400 below a 40px notch
        final l = _layout(
          ViewportFit.contain,
          const ui.Size(800, 480),
          safe: safe,
        );
        expect(l.contentRect, const ui.Rect.fromLTWH(0, 40, 800, 400));
      },
    );

    test('avoidSystemUi: false ignores the safe area', () {
      final safe = ui.RRect.fromLTRBAndCorners(0, 40, 800, 440);
      final l = ViewportManager(
        const ViewportConfig(targetAspectRatio: 2, avoidSystemUi: false),
      ).computeLayout(const ui.Size(800, 480), safe);
      expect(l.contentRect.height, lessThanOrEqualTo(480));
      expect(
        l.contentRect.top,
        40,
        reason: 'centred in the full 800x480 screen, 400 tall',
      );
    });

    test('screenToContent and contentToScreen are inverses', () {
      final l = _layout(ViewportFit.contain, const ui.Size(1200, 400));
      const p = ui.Offset(300, 120);
      expect(l.screenToContent(p), const ui.Offset(100, 120));
      expect(l.contentToScreen(l.screenToContent(p)), p);
    });
  });

  testWidgets(
    'a tap in a letterboxed EngineView is reported in world coordinates of the drawn area',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final world = World(width: 800, height: 400);
      registerCoreComponents(world);
      registerFlutterComponents(world);
      ui.Offset? tapped;

      await tester.pumpWidget(
        MaterialApp(
          home: EngineView(
            world: world,
            atlasRegistry: AtlasRegistry(),
            camera: Camera(x: 400, y: 200),
            viewportConfig: const ViewportConfig(
              targetAspectRatio: 2,
              avoidSystemUi: false,
            ),
            onWorldTap: (p) => tapped = p,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      // The 800x400 game is centred in 1200x400, so its left edge is at x = 200. With the camera at
      // (400, 200) and zoom 1, the game's top-left is world (0, 0).
      await tester.tapAt(const Offset(200 + 100, 50));
      expect(tapped, isNotNull);
      expect(tapped!.dx, closeTo(100, 0.5));
      expect(tapped!.dy, closeTo(50, 0.5));
    },
  );
}
