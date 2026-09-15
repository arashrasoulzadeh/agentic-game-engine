/// Marks an entity as affected by `GravitySystem`. `scale` lets
/// individual entities feel heavier/lighter (e.g. reduced gravity while
/// a jump button is held) without a separate component type per case.
class Gravity {
  double scale;

  /// Extra multiplier `GravitySystem` applies on top of [scale] only
  /// while the entity is actually falling (`Velocity.y > 0`) — `1`
  /// (the default) means no asymmetry, identical to every jump this
  /// engine had before this field existed. A value above `1` (e.g.
  /// `1.5`-`2`) makes the descent snappier/faster than the rise for the
  /// same `PlatformerController.jumpSpeed`, the standard "floaty rise,
  /// fast fall" platformer feel (Celeste, Hollow Knight, etc.) — tuning
  /// fall weight independently of jump height/reach, rather than
  /// [scale] alone, which would speed up (or slow down) both equally
  /// and change how high/far the jump itself reaches too.
  double fallMultiplier;

  Gravity({this.scale = 1, this.fallMultiplier = 1});

  Map<String, dynamic> toJson() => {'scale': scale, 'fallMultiplier': fallMultiplier};

  factory Gravity.fromJson(Map<String, dynamic> json) => Gravity(
        scale: (json['scale'] as num?)?.toDouble() ?? 1,
        fallMultiplier: (json['fallMultiplier'] as num?)?.toDouble() ?? 1,
      );
}
