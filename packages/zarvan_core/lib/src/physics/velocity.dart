import 'dart:math' as math;

/// Units per second. Both components default to 0, so `Velocity()` is "at
/// rest", the usual starting value for something a system will push around.
class Velocity {
  double x, y;
  Velocity([this.x = 0, this.y = 0]);

  double get magnitude => math.sqrt(x * x + y * y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory Velocity.fromJson(Map<String, dynamic> json) =>
      Velocity((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}
