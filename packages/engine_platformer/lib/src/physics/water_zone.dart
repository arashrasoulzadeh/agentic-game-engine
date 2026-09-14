/// An axis-aligned rectangle of water — same `Position`-is-the-center
/// convention as `PlatformBody`, but purely a physics-altering zone
/// (never blocks movement the way a `PlatformBody`/solid tile does).
/// `WaterPhysicsSystem` reads this against every `PlatformerController`
/// entity's current position each tick.
class WaterZone {
  double width;
  double height;

  /// Downward speed an entity's `Velocity.y` is clamped to while
  /// submerged — water's buoyancy resisting a fall, distinct from (and
  /// generally much lower than) however fast `GravitySystem` would
  /// otherwise accelerate it in open air.
  double maxFallSpeed;

  /// Upward speed applied as a one-shot "stroke" the tick
  /// `PlatformerController.jumpRequested` is set while submerged —
  /// `WaterPhysicsSystem` consumes the request itself (so
  /// `JumpSystem` right after it doesn't also try to jump), giving a
  /// swim state genuinely distinct from a walk/jump's single-impulse
  /// launch: repeated presses give repeated strokes rather than one
  /// jump arc.
  double swimUpSpeed;

  WaterZone(this.width, this.height, {this.maxFallSpeed = 80, this.swimUpSpeed = 140});

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'maxFallSpeed': maxFallSpeed,
        'swimUpSpeed': swimUpSpeed,
      };

  factory WaterZone.fromJson(Map<String, dynamic> json) => WaterZone(
        (json['width'] as num).toDouble(),
        (json['height'] as num).toDouble(),
        maxFallSpeed: (json['maxFallSpeed'] as num?)?.toDouble() ?? 80,
        swimUpSpeed: (json['swimUpSpeed'] as num?)?.toDouble() ?? 140,
      );
}
