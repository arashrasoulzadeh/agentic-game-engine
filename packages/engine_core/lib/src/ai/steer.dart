import 'dart:math' as math;

import '../ecs/deterministic_random.dart';
import '../physics/position.dart';
import '../physics/velocity.dart';
import 'steering.dart' as prim;

/// What a steering rule can look at: where the entity is, how it is moving,
/// what it is steering toward, and a seeded random source for wandering.
class SteerContext {
  const SteerContext({
    required this.self,
    required this.current,
    required this.rng,
    this.target,
  });

  final Position self;
  final Velocity current;
  final DeterministicRandom rng;

  /// What to seek, flee or arrive at; null for rules that need no target
  /// (a rule that does need one returns zero velocity when it is null).
  final Position? target;
}

/// One steering rule: a context in, the velocity it wants out.
typedef SteerRule = Velocity Function(SteerContext context);

/// Steering rules that compose, built on the primitives in `steering.dart`
/// (`seek`, `arrive`, `wander`).
///
/// ```dart
/// final rule = Steer.blend([
///   (Steer.arrive(80, slowRadius: 40), 1.0),
///   (Steer.wander(0.4, 80), 0.3),
/// ], maxSpeed: 80);
/// final v = rule(SteerContext(self: pos, current: vel, rng: rng, target: goal));
/// ```
abstract final class Steer {
  /// Straight toward the target at [maxSpeed] ([prim.seek]).
  static SteerRule seek(double maxSpeed) =>
      (c) => c.target == null
      ? Velocity(0, 0)
      : prim.seek(c.self, c.target!, maxSpeed);

  /// Straight away from the target at [maxSpeed].
  static SteerRule flee(double maxSpeed) => (c) {
    if (c.target == null) return Velocity(0, 0);
    final v = prim.seek(c.self, c.target!, maxSpeed);
    return Velocity(-v.x, -v.y);
  };

  /// Toward the target, slowing inside [slowRadius] ([prim.arrive]).
  static SteerRule arrive(double maxSpeed, {required double slowRadius}) =>
      (c) => c.target == null
      ? Velocity(0, 0)
      : prim.arrive(c.self, c.target!, maxSpeed, slowRadius);

  /// A drifting heading that changes by up to [jitter] radians per call
  /// ([prim.wander]).
  static SteerRule wander(double jitter, double maxSpeed) =>
      (c) => prim.wander(c.current, jitter, maxSpeed, c.rng);

  /// The weighted sum of several rules, each as `(rule, weight)`, capped at
  /// [maxSpeed] so blending never makes an entity faster than its limit.
  static SteerRule blend(
    List<(SteerRule, double)> parts, {
    required double maxSpeed,
  }) => (c) {
    var x = 0.0, y = 0.0;
    for (final (rule, weight) in parts) {
      final v = rule(c);
      x += v.x * weight;
      y += v.y * weight;
    }
    final speed = math.sqrt(x * x + y * y);
    if (speed > maxSpeed && speed > 0) {
      x = x / speed * maxSpeed;
      y = y / speed * maxSpeed;
    }
    return Velocity(x, y);
  };

  /// The first rule that wants to move (non-zero velocity); stands still if
  /// none does. Use it for fallbacks: flee when threatened, else arrive.
  static SteerRule firstMoving(List<SteerRule> rules) => (c) {
    for (final rule in rules) {
      final v = rule(c);
      if (v.x != 0 || v.y != 0) return v;
    }
    return Velocity(0, 0);
  };

  /// [rule] only while [when] is true, otherwise zero velocity: "flee only
  /// within 100 of the target" without a custom behavior class.
  static SteerRule onlyWhen(bool Function(SteerContext) when, SteerRule rule) =>
      (c) => when(c) ? rule(c) : Velocity(0, 0);

  /// True when the target is within [radius] of the entity; for [onlyWhen].
  static bool Function(SteerContext) within(double radius) => (c) {
    final t = c.target;
    if (t == null) return false;
    final dx = t.x - c.self.x, dy = t.y - c.self.y;
    return dx * dx + dy * dy <= radius * radius;
  };
}
