import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    camera.follow(999, 999,
        viewportSize: const Size(800, 600), worldWidth: 400, worldHeight: 300);
    expect(camera.x, 200);
    expect(camera.y, 150);
  });

  test('follow clamps so the viewport never shows past world bounds', () {
    final camera = Camera();
    camera.follow(10, 10,
        viewportSize: const Size(800, 600), worldWidth: 2000, worldHeight: 2000);
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
}
