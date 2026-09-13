import 'dart:math';
import 'dart:ui';

/// World-to-screen viewport transform. One camera per `EngineView` — not
/// an ECS component, since a camera isn't game-simulation state an agent
/// needs to read/patch, it's a rendering concern.
class Camera {
  double x;
  double y;
  double zoom;

  final Random _random;

  double _shakeMagnitude = 0;
  double _shakeDuration = 0;
  double _shakeRemaining = 0;
  double _shakeOffsetX = 0;
  double _shakeOffsetY = 0;

  Camera({this.x = 0, this.y = 0, this.zoom = 1, Random? random}) : _random = random ?? Random();

  /// Starts a screen shake: a random jitter offset up to [magnitude]
  /// (world units, before `zoom`) in both axes, linearly decaying to
  /// `0` over [duration] seconds. Calling this again while one is
  /// already running replaces it (doesn't stack) — the common "another
  /// hit landed mid-shake" case just restarts at the new magnitude
  /// rather than compounding.
  void shake(double magnitude, double duration) {
    _shakeMagnitude = magnitude;
    _shakeDuration = duration;
    _shakeRemaining = duration;
  }

  /// Advances the active shake (if any) by [dt] and recomputes this
  /// frame's jitter offset — called once per frame by `EngineView`,
  /// regardless of whether this camera is following an entity (a
  /// static camera still needs to shake on e.g. an explosion). Not
  /// something a game normally calls itself.
  void update(double dt) {
    if (_shakeRemaining <= 0) {
      _shakeOffsetX = 0;
      _shakeOffsetY = 0;
      return;
    }
    _shakeRemaining = (_shakeRemaining - dt).clamp(0, _shakeDuration);
    final falloff = _shakeDuration <= 0 ? 0.0 : _shakeRemaining / _shakeDuration;
    final magnitude = _shakeMagnitude * falloff;
    _shakeOffsetX = (_random.nextDouble() * 2 - 1) * magnitude;
    _shakeOffsetY = (_random.nextDouble() * 2 - 1) * magnitude;
  }

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
      (worldX - x) * zoom + viewportSize.width / 2 + _shakeOffsetX * zoom,
      (worldY - y) * zoom + viewportSize.height / 2 + _shakeOffsetY * zoom,
    );
  }

  /// Inverse of [worldToScreen] — where in world space a tap/click at
  /// [screen] landed, e.g. for hit-testing `Button` entities against a
  /// pointer event. `EngineView` calls this so a `Scene`'s tap handler
  /// never has to know about screen coordinates or the camera at all.
  /// Accounts for the current shake offset too, so a tap during a
  /// shake still resolves to the right world position rather than one
  /// skewed by the jitter.
  Offset screenToWorld(Offset screen, Size viewportSize) {
    return Offset(
      (screen.dx - _shakeOffsetX * zoom - viewportSize.width / 2) / zoom + x,
      (screen.dy - _shakeOffsetY * zoom - viewportSize.height / 2) / zoom + y,
    );
  }
}
