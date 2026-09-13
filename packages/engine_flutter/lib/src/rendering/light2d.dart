/// A point light for `EngineView`'s ambient-darkness lighting pass
/// (see `EngineView.ambientBrightness`) — a torch glow, a flashlight
/// highlight, an explosion flash. Reveals the already-drawn scene
/// through the darkness rather than recoloring it: this is "basic"
/// lighting on purpose (brightness/falloff only, no colored tint, no
/// shadow casting from `TileMap`/`Collider` geometry) — a full
/// shadow-casting system is a much bigger scope nothing has asked for
/// yet, and a real torch/flashlight effect is already well served by
/// just this.
class Light2D {
  double radius;

  /// How fully this light reveals the scene at its center, `0`
  /// (invisible — no reveal at all) to `1` (fully revealed, the
  /// scene's true colors), falling off smoothly to `0` again at
  /// [radius]'s edge.
  double intensity;

  Light2D({this.radius = 100, this.intensity = 1});

  Map<String, dynamic> toJson() => {
        'radius': radius,
        'intensity': intensity,
      };

  factory Light2D.fromJson(Map<String, dynamic> json) => Light2D(
        radius: (json['radius'] as num?)?.toDouble() ?? 100,
        intensity: (json['intensity'] as num?)?.toDouble() ?? 1,
      );
}
