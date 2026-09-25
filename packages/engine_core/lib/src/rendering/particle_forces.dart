import '../ecs/entity.dart';

/// Force field affecting particles in a radius.
/// Can attract (positive strength), repel (negative), or create directional wind.
/// Add to an entity with a [Position] to create a force field.
/// Multiple force fields stack additively on particles within range.
class ParticleForces {
  /// Radius of the force field. Particles outside this range are unaffected.
  double radius;

  /// Strength of the force. Positive = attract toward center, negative = repel away.
  /// Units: world pixels per second squared (acceleration).
  double strength;

  /// If true, applies a constant directional force (wind) instead of radial.
  /// Direction is given by [windDirection] radians.
  bool isWind;

  /// Direction of wind in radians (0 = right, pi/2 = down, etc.).
  /// Only used if [isWind] is true.
  double windDirection;

  /// Falloff exponent. Higher = sharper falloff near edge.
  /// 1 = linear, 2 = quadratic, etc.
  double falloffExponent;

  ParticleForces({
    this.radius = 100,
    this.strength = 500,
    this.isWind = false,
    this.windDirection = 0,
    this.falloffExponent = 2,
  });

  Map<String, dynamic> toJson() => {
        'radius': radius,
        'strength': strength,
        'isWind': isWind,
        'windDirection': windDirection,
        'falloffExponent': falloffExponent,
      };

  factory ParticleForces.fromJson(Map<String, dynamic> json) => ParticleForces(
        radius: (json['radius'] as num?)?.toDouble() ?? 100,
        strength: (json['strength'] as num?)?.toDouble() ?? 500,
        isWind: (json['isWind'] as bool?) ?? false,
        windDirection: (json['windDirection'] as num?)?.toDouble() ?? 0,
        falloffExponent: (json['falloffExponent'] as num?)?.toDouble() ?? 2,
      );
}