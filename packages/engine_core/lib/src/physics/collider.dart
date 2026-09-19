class Collider {
  double radius;

  /// Whether a `Light2D` with `castsShadows` on treats this entity as
  /// solid for shadow-casting purposes, the same way `TileMap` solid
  /// tiles already are — `false` (default, unchanged behavior) for
  /// most colliders (a coin, an enemy's hurtbox) that shouldn't block
  /// light just because they physically collide with something. Set
  /// this on props meant to look solid (a crate, a pillar, a closed
  /// door) that aren't baked into a level's tile grid.
  bool blocksLight;

  /// Whether `CollisionSystem` applies its elastic velocity-swap
  /// response when this collider overlaps another one. `true`
  /// (default, unchanged behavior) — the original "two moving bodies
  /// bounce off each other" behavior. `false` opts *out* of the push
  /// response while still emitting `CollisionEvent` as normal (a
  /// `CollisionSystem` swap only ever requires the *other* side to
  /// also be `pushable`, so `false` here is enough on its own to
  /// disable it for every pair this entity is part of) — for a body
  /// with its own hand-written `Velocity` logic (an AI-driven enemy
  /// deciding its own patrol/chase speed every tick, say) that
  /// shouldn't have that `Velocity` silently overwritten by whatever
  /// the other side of a touch happened to be moving at. Found live:
  /// a patrolling enemy in constant contact with the player swapped
  /// velocities with it every single tick, handing the player the
  /// enemy's `vel.y` (always 0, that enemy has no gravity) and
  /// erasing several ticks' worth of accumulated fall speed at once —
  /// read by `GravitySystem`/`TileCollisionSystem` the very next tick
  /// as "just landed", which visibly popped the player like a small
  /// jump on every approach.
  bool pushable;

  /// Collision group this entity belongs to (bitmask). Default `1`.
  /// Entities only collide if `(this.collisionGroup & other.collisionMask) != 0`
  /// AND `(other.collisionGroup & this.collisionMask) != 0`.
  int collisionGroup;

  /// Collision mask determining which groups this entity can collide with (bitmask).
  /// Default `-1` (all bits set, collides with all groups).
  int collisionMask;

  Collider(this.radius,
      {this.blocksLight = false,
      this.pushable = true,
      this.collisionGroup = 1,
      this.collisionMask = -1});

  Map<String, dynamic> toJson() =>
      {'radius': radius, 'blocksLight': blocksLight, 'pushable': pushable,
       'collisionGroup': collisionGroup, 'collisionMask': collisionMask};
  factory Collider.fromJson(Map<String, dynamic> json) => Collider(
        (json['radius'] as num).toDouble(),
        blocksLight: json['blocksLight'] as bool? ?? false,
        pushable: json['pushable'] as bool? ?? true,
        collisionGroup: json['collisionGroup'] as int? ?? 1,
        collisionMask: json['collisionMask'] as int? ?? -1,
      );
}
