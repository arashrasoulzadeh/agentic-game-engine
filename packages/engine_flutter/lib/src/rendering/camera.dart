import 'dart:math';
import 'dart:ui';

/// Axis for camera shake.
enum ShakeAxis { x, y, both }

/// A single shake effect that can be combined with others.
class _ShakeEffect {
  final double magnitude;
  final double duration;
  double remaining;
  final double frequency;
  final double decay;
  final bool impulse;
  final ShakeAxis axis;

  _ShakeEffect({
    required this.magnitude,
    required this.duration,
    this.frequency = 1.0,
    this.decay = 1.0,
    this.impulse = false,
    this.axis = ShakeAxis.both,
  }) : remaining = duration;

  bool get isFinished => remaining <= 0;

  void update(double dt) {
    if (remaining <= 0) return;
    remaining = (remaining - dt).clamp(0.0, duration);
  }

  double get progress => duration <= 0 ? 1.0 : 1.0 - remaining / duration;

  double get falloff {
    if (duration <= 0) return 0.0;
    final t = remaining / duration;
    if (impulse) {
      // Impulse: sharp decay (quadratic)
      return t * t;
    } else {
      // Sustained: linear decay with optional decay modifier
      return pow(t, decay).toDouble();
    }
  }

  double get currentMagnitude => magnitude * falloff;
}

/// World-to-screen viewport transform. One camera per `EngineView` — not
/// an ECS component, since a camera isn't game-simulation state an agent
/// needs to read/patch, it's a rendering concern.
class Camera {
  double x;
  double y;
  double zoom;

  final Random _random;

  final List<_ShakeEffect> _shakes = [];
  double _shakeOffsetX = 0;
  double _shakeOffsetY = 0;

  Camera({this.x = 0, this.y = 0, this.zoom = 1, Random? random}) : _random = random ?? Random();

  /// Starts a screen shake effect.
  ///
  /// [magnitude] - maximum offset in world units (before `zoom`)
  /// [duration] - duration in seconds
  /// [frequency] - oscillations per second (default 1.0)
  /// [decay] - decay curve exponent (1.0 = linear, >1 = faster decay, <1 = slower)
  /// [impulse] - if true, sharp impulse decay; if false, sustained shake
  /// [axis] - which axis to shake (default ShakeAxis.both)
  /// [stack] - if true, adds to existing shakes; if false, replaces all
  void shake({
    required double magnitude,
    required double duration,
    double frequency = 1.0,
    double decay = 1.0,
    bool impulse = false,
    ShakeAxis axis = ShakeAxis.both,
    bool stack = false,
  }) {
    if (!stack) {
      _shakes.clear();
    }
    _shakes.add(_ShakeEffect(
      magnitude: magnitude,
      duration: duration,
      frequency: frequency,
      decay: decay,
      impulse: impulse,
      axis: axis,
    ));
  }

  /// Advances all active shake effects by [dt] and recomputes this
  /// frame's jitter offset — called once per frame by `EngineView`,
  /// regardless of whether this camera is following an entity (a
  /// static camera still needs to shake on e.g. an explosion). Not
  /// something a game normally calls itself.
  void update(double dt) {
    _shakeOffsetX = 0;
    _shakeOffsetY = 0;

    // Remove finished shakes
    _shakes.removeWhere((s) => s.isFinished);

    // Update remaining time for each shake
    for (final shake in _shakes) {
      shake.update(dt);
    }

    // Compute combined offset from all active shakes
    double totalOffsetX = 0;
    double totalOffsetY = 0;

    for (final shake in _shakes) {
      final mag = shake.currentMagnitude;
      if (mag <= 0) continue;

      // Apply frequency by using a time-based oscillator
      final jitterX = (_random.nextDouble() * 2 - 1) * mag;
      final jitterY = (_random.nextDouble() * 2 - 1) * mag;

      if (shake.axis == ShakeAxis.x) {
        totalOffsetX += jitterX;
      } else if (shake.axis == ShakeAxis.y) {
        totalOffsetY += jitterY;
      } else {
        totalOffsetX += jitterX;
        totalOffsetY += jitterY;
      }
    }

    _shakeOffsetX = totalOffsetX;
    _shakeOffsetY = totalOffsetY;
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