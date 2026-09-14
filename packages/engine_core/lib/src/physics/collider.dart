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

  Collider(this.radius, {this.blocksLight = false});

  Map<String, dynamic> toJson() => {'radius': radius, 'blocksLight': blocksLight};
  factory Collider.fromJson(Map<String, dynamic> json) => Collider(
        (json['radius'] as num).toDouble(),
        blocksLight: json['blocksLight'] as bool? ?? false,
      );
}
