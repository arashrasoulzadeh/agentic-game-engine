import 'dart:ui';

/// World-to-screen viewport transform. One camera per `EngineView` — not
/// an ECS component, since a camera isn't game-simulation state an agent
/// needs to read/patch, it's a rendering concern.
class Camera {
  double x;
  double y;
  double zoom;

  Camera({this.x = 0, this.y = 0, this.zoom = 1});

  /// Re-centers the camera on [worldX]/[worldY], optionally clamped so the
  /// viewport never shows past [worldWidth]/[worldHeight] bounds.
  void follow(
    double worldX,
    double worldY, {
    Size? viewportSize,
    double? worldWidth,
    double? worldHeight,
  }) {
    x = worldX;
    y = worldY;
    if (viewportSize == null || worldWidth == null || worldHeight == null) {
      return;
    }
    final halfW = viewportSize.width / (2 * zoom);
    final halfH = viewportSize.height / (2 * zoom);
    if (worldWidth > halfW * 2) {
      x = x.clamp(halfW, worldWidth - halfW);
    } else {
      x = worldWidth / 2;
    }
    if (worldHeight > halfH * 2) {
      y = y.clamp(halfH, worldHeight - halfH);
    } else {
      y = worldHeight / 2;
    }
  }

  Offset worldToScreen(double worldX, double worldY, Size viewportSize) {
    return Offset(
      (worldX - x) * zoom + viewportSize.width / 2,
      (worldY - y) * zoom + viewportSize.height / 2,
    );
  }

  /// Inverse of [worldToScreen] — where in world space a tap/click at
  /// [screen] landed, e.g. for hit-testing `Button` entities against a
  /// pointer event. `EngineView` calls this so a `Scene`'s tap handler
  /// never has to know about screen coordinates or the camera at all.
  Offset screenToWorld(Offset screen, Size viewportSize) {
    return Offset(
      (screen.dx - viewportSize.width / 2) / zoom + x,
      (screen.dy - viewportSize.height / 2) / zoom + y,
    );
  }
}
