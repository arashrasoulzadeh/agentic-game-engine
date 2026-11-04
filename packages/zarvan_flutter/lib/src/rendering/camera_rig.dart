import 'dart:math';
import 'dart:ui' show Rect, Size;

import 'camera.dart';

/// How a camera follows its target: a dead-zone the target can move in without
/// the camera reacting, a look-ahead that leads the camera in the direction of
/// travel, easing, and a level rectangle to stay inside.
///
/// Give one to `EngineView(cameraRig:)` (it needs `cameraFollowEntity` too), or
/// call [update] yourself each frame. All distances are world units.
class CameraRig {
  CameraRig({
    this.deadZoneWidth = 0,
    this.deadZoneHeight = 0,
    this.lookAhead = 0,
    this.lookAheadSpeed = 120,
    this.lookAheadHalfLife = 0.25,
    this.halfLife = 0,
    this.bounds,
  });

  /// The camera holds still while the target stays within this window around
  /// the camera's centre, and moves just far enough to keep it in. 0 = no
  /// dead-zone (the camera centres on the target).
  double deadZoneWidth;
  double deadZoneHeight;

  /// How far ahead of the target the camera aims when it moves at
  /// [lookAheadSpeed] or faster (less at lower speeds); 0 = none.
  double lookAhead;
  double lookAheadSpeed;

  /// Seconds for the look-ahead offset to cover half the distance to its goal,
  /// so reversing direction does not whip the camera.
  double lookAheadHalfLife;

  /// Easing of the camera itself: the remaining distance halves every
  /// [halfLife] seconds; 0 or less snaps.
  double halfLife;

  /// The rectangle the viewport must stay inside (a level's extent); null
  /// leaves the camera unclamped.
  Rect? bounds;

  double _lookX = 0;
  double _lookY = 0;

  /// The current look-ahead offset, for debugging and tests.
  (double, double) get lookOffset => (_lookX, _lookY);

  /// Moves [camera] toward the target at ([targetX], [targetY]) moving with
  /// ([velocityX], [velocityY]), for a frame of [dt] seconds. [defaultBounds]
  /// (the world) applies when [bounds] is not set.
  void update(
    Camera camera, {
    required double targetX,
    required double targetY,
    double velocityX = 0,
    double velocityY = 0,
    required double dt,
    Size? viewportSize,
    Rect? defaultBounds,
  }) {
    // Look-ahead: lean toward where the target is heading, eased.
    final speed = sqrt(velocityX * velocityX + velocityY * velocityY);
    var goalX = 0.0, goalY = 0.0;
    if (lookAhead > 0 && speed > 1e-6) {
      final strength = min(1.0, speed / max(lookAheadSpeed, 1e-6));
      goalX = velocityX / speed * lookAhead * strength;
      goalY = velocityY / speed * lookAhead * strength;
    }
    final lt = _ease(lookAheadHalfLife, dt);
    _lookX += (goalX - _lookX) * lt;
    _lookY += (goalY - _lookY) * lt;

    final aimX = targetX + _lookX;
    final aimY = targetY + _lookY;

    // Dead-zone: only the part of the offset outside the window counts.
    final dx = _outside(aimX - camera.x, deadZoneWidth / 2);
    final dy = _outside(aimY - camera.y, deadZoneHeight / 2);

    final t = _ease(halfLife, dt);
    camera.x += dx * t;
    camera.y += dy * t;

    final area = bounds ?? defaultBounds;
    if (area != null && viewportSize != null)
      camera.clampTo(area, viewportSize);
  }

  /// Snaps the camera onto the target and forgets the look-ahead, for a
  /// teleport or a scene start.
  void reset(Camera camera, double targetX, double targetY) {
    _lookX = 0;
    _lookY = 0;
    camera.x = targetX;
    camera.y = targetY;
  }

  static double _outside(double offset, double half) {
    if (offset > half) return offset - half;
    if (offset < -half) return offset + half;
    return 0;
  }

  static double _ease(double halfLife, double dt) =>
      halfLife <= 0 ? 1.0 : 1 - pow(0.5, dt / halfLife).toDouble();
}
