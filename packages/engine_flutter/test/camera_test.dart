import 'dart:math';

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  cameraSmoothFollowTests();
  test('worldToScreen centers the camera position in the viewport', () {
    final camera = Camera(x: 0, y: 0, zoom: 1);
    final screen = camera.worldToScreen(0, 0, const Size(800, 600));
    expect(screen, const Offset(400, 300));
  });

  test('worldToScreen scales offsets by zoom', () {
    final camera = Camera(x: 0, y: 0, zoom: 2);
    final screen = camera.worldToScreen(100, 0, const Size(800, 600));
    expect(screen, const Offset(600, 300));
  });

  test('follow centers on target when world is smaller than viewport', () {
    final camera = Camera();
    camera.follow(
      999,
      999,
      viewportSize: const Size(800, 600),
      worldWidth: 400,
      worldHeight: 300,
    );
    expect(camera.x, 200);
    expect(camera.y, 150);
  });

  test('follow clamps so the viewport never shows past world bounds', () {
    final camera = Camera();
    camera.follow(
      10,
      10,
      viewportSize: const Size(800, 600),
      worldWidth: 2000,
      worldHeight: 2000,
    );
    expect(camera.x, 400); // clamped to half-viewport-width
    expect(camera.y, 300);
  });

  test('screenToWorld is the exact inverse of worldToScreen', () {
    final camera = Camera(x: 120, y: -40, zoom: 1.5);
    const viewport = Size(800, 600);
    const worldPoint = Offset(37, 210);

    final screen = camera.worldToScreen(worldPoint.dx, worldPoint.dy, viewport);
    final backToWorld = camera.screenToWorld(screen, viewport);

    expect(backToWorld.dx, closeTo(worldPoint.dx, 1e-9));
    expect(backToWorld.dy, closeTo(worldPoint.dy, 1e-9));
  });

  group('shake', () {
    test('before shake() is called, worldToScreen is unaffected', () {
      final camera = Camera(x: 0, y: 0, zoom: 1, random: Random(1));
      camera.update(0.016);
      expect(
        camera.worldToScreen(0, 0, const Size(800, 600)),
        const Offset(400, 300),
      );
    });

    test('an active shake perturbs worldToScreen by a bounded jitter', () {
      final camera = Camera(x: 0, y: 0, zoom: 1, random: Random(1));
      camera.shake(magnitude: 20, duration: 1);
      camera.update(0.016);

      final screen = camera.worldToScreen(0, 0, const Size(800, 600));
      // Some nonzero jitter was applied...
      expect(screen, isNot(const Offset(400, 300)));
      // ...bounded by the requested magnitude (scaled by zoom, here 1).
      expect((screen.dx - 400).abs(), lessThanOrEqualTo(20));
      expect((screen.dy - 300).abs(), lessThanOrEqualTo(20));
    });

    test('shake magnitude decays to zero once duration has fully elapsed', () {
      final camera = Camera(x: 0, y: 0, zoom: 1, random: Random(1));
      camera.shake(magnitude: 20, duration: 1);
      camera.update(1.5); // past the full 1-second duration

      expect(
        camera.worldToScreen(0, 0, const Size(800, 600)),
        const Offset(400, 300),
      );
    });

    test(
      'calling shake again replaces the running shake instead of stacking',
      () {
        final camera = Camera(x: 0, y: 0, zoom: 1, random: Random(1));
        camera.shake(
          magnitude: 5,
          duration: 10,
        ); // long-running, small magnitude
        camera.update(0.016);
        camera.shake(
          magnitude: 50,
          duration: 1,
        ); // a bigger hit lands mid-shake
        camera.update(0.016);

        final screen = camera.worldToScreen(0, 0, const Size(800, 600));
        // Bounded by the *new* magnitude, not the sum of both.
        expect((screen.dx - 400).abs(), lessThanOrEqualTo(50));
        expect((screen.dy - 300).abs(), lessThanOrEqualTo(50));
      },
    );

    test(
      'screenToWorld remains the exact inverse of worldToScreen during an active shake',
      () {
        final camera = Camera(x: 120, y: -40, zoom: 1.5, random: Random(7));
        camera.shake(magnitude: 30, duration: 1);
        camera.update(0.016);
        const viewport = Size(800, 600);
        const worldPoint = Offset(37, 210);

        final screen = camera.worldToScreen(
          worldPoint.dx,
          worldPoint.dy,
          viewport,
        );
        final backToWorld = camera.screenToWorld(screen, viewport);

        expect(backToWorld.dx, closeTo(worldPoint.dx, 1e-9));
        expect(backToWorld.dy, closeTo(worldPoint.dy, 1e-9));
      },
    );
  });
}

void cameraSmoothFollowTests() {
  test('followSmooth halves the remaining distance every halfLife', () {
    final camera = Camera();
    camera.followSmooth(100, 0, 0.15, halfLife: 0.15);
    expect(camera.x, closeTo(50, 1e-9));
    camera.followSmooth(100, 0, 0.15, halfLife: 0.15);
    expect(camera.x, closeTo(75, 1e-9));
  });

  test('followSmooth is frame-rate independent', () {
    final a = Camera(), b = Camera();
    a.followSmooth(100, 0, 0.2);
    for (var i = 0; i < 4; i++) {
      b.followSmooth(100, 0, 0.05);
    }
    expect(a.x, closeTo(b.x, 1e-9));
  });

  test('followSmooth clamps to world bounds and snaps with halfLife 0', () {
    final camera = Camera();
    camera.followSmooth(
      1000,
      0,
      1,
      halfLife: 0,
      viewportSize: const Size(100, 100),
      worldWidth: 400,
      worldHeight: 400,
    );
    expect(camera.x, 350);
  });
}
