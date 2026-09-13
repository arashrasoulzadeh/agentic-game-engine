/// Marks an entity as pushable: something a solid entity moving into it
/// shoves aside horizontally, instead of `CollisionSystem`'s default
/// elastic velocity swap or just passing through. A crate, a boulder, a
/// block puzzle piece.
///
/// Deliberately doesn't handle being blocked by a wall itself —
/// `PushableSystem` only ever decides "is this being pushed, and which
/// way," writing that to `Velocity.x`. For a pushable that should stop
/// at a wall instead of being shoved through it, also give the entity a
/// `PlatformerController` (+ typically `Gravity`) from `engine_platformer`
/// and register it with `installPlatformerSystems`/`TileCollisionSystem`
/// like any other physics entity — wall-blocking then comes for free
/// from systems that already exist, rather than `PushableSystem`
/// duplicating tile/platform collision logic itself. A top-down game
/// with no walls at all can use `Pushable` with nothing else.
class Pushable {
  /// Horizontal speed while actively being pushed. A pushable has no
  /// momentum of its own — `PushableSystem` sets `Velocity.x` to
  /// exactly this (signed by push direction) or `0` every tick, rather
  /// than accelerating/decelerating, matching classic crate-pushing
  /// feel (it moves only while something is actively pushing it, and
  /// stops the instant nothing is).
  double pushSpeed;

  Pushable({this.pushSpeed = 80});

  Map<String, dynamic> toJson() => {'pushSpeed': pushSpeed};

  factory Pushable.fromJson(Map<String, dynamic> json) =>
      Pushable(pushSpeed: (json['pushSpeed'] as num?)?.toDouble() ?? 80);
}
