import 'dart:math' as math;

import '../ecs/deterministic_random.dart';
import '../physics/velocity.dart';
import '../physics/position.dart';

/// Steering-behavior primitives — plain functions (not `Behavior` classes)
/// that return a [Velocity]. Consumed by `Behavior` implementations
/// like `FleeBehavior`, `FollowBehavior`, `AvoidanceBehavior`.
///
/// Mirrors `collision_math.dart`'s pattern: shared math extracted so
/// multiple behaviors/systems don't duplicate it.

/// Returns a velocity pointing straight from [from] to [to] at [maxSpeed].
Velocity seek(Position from, Position to, double maxSpeed) {
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  final dist = math.sqrt(dx * dx + dy * dy);
  if (dist < 1e-6) return Velocity(0, 0);
  return Velocity((dx / dist) * maxSpeed, (dy / dist) * maxSpeed);
}

/// Like [seek] but linearly scales speed down inside [slowRadius] so
/// the entity decelerates smoothly instead of snapping to a stop.
/// Outside [slowRadius], returns full [maxSpeed] toward the target.
/// At distance 0, returns zero velocity.
Velocity arrive(Position from, Position to, double maxSpeed, double slowRadius) {
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  final dist = math.sqrt(dx * dx + dy * dy);
  if (dist < 1e-6) return Velocity(0, 0);
  if (dist >= slowRadius) return seek(from, to, maxSpeed);
  final speed = maxSpeed * (dist / slowRadius);
  return Velocity((dx / dist) * speed, (dy / dist) * speed);
}

/// Adds a small random perturbation to [current] velocity and clamps
/// to [maxSpeed]. Uses [rng] for reproducibility (pass a
/// `DeterministicRandom` to keep replay determinism).
///
/// [jitter] controls how much the heading can change per call (in px/s).
/// Typical usage: call once per tick to get a wandering entity that
/// drifts smoothly rather than teleporting.
Velocity wander(Velocity current, double jitter, double maxSpeed, DeterministicRandom rng) {
  // Random angle offset in [-jitter, +jitter]
  final angle = current.angle + rng.nextDouble() * 2 * jitter - jitter;
  final vx = maxSpeed * math.cos(angle);
  final vy = maxSpeed * math.sin(angle);
  return Velocity(vx, vy);
}

/// Extension on [Velocity] for convenience.
extension VelocitySteering on Velocity {
  /// Angle of this velocity in radians.
  double get angle => math.atan2(y, x);

  /// Returns a new velocity with the same angle but magnitude [speed].
  Velocity withSpeed(double speed) {
    final a = angle;
    return Velocity(speed * math.cos(a), speed * math.sin(a));
  }
}