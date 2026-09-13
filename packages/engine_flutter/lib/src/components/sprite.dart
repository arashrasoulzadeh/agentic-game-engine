/// Data-only sprite reference: which atlas, which named region, and a
/// simple transform. Resolved against an `AtlasRegistry` at render time,
/// which keeps this component plain-JSON serializable for agent authoring.
class Sprite {
  String atlasId;
  String region;
  double rotation;
  double scaleX;
  double scaleY;

  /// Draw order relative to every other renderable (`Sprite`,
  /// `ParallaxLayer`, `TileMap`, `Particle`) in the world — lower draws
  /// first (further back), higher draws last (further forward). Ties
  /// (the default: everything at 0) fall back to the engine's original
  /// draw order (parallax, then tiles, then sprites, then particles;
  /// within a kind, `ComponentStore` insertion order) — see
  /// `EngineView`'s README section on z-index for the exact tie-break
  /// rule and how batching interacts with it.
  int zIndex;

  Sprite(
    this.atlasId,
    this.region, {
    this.rotation = 0,
    this.scaleX = 1,
    this.scaleY = 1,
    this.zIndex = 0,
  });

  Map<String, dynamic> toJson() => {
        'atlasId': atlasId,
        'region': region,
        'rotation': rotation,
        'scaleX': scaleX,
        'scaleY': scaleY,
        'zIndex': zIndex,
      };

  factory Sprite.fromJson(Map<String, dynamic> json) => Sprite(
        json['atlasId'] as String,
        json['region'] as String,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        scaleX: (json['scaleX'] as num?)?.toDouble() ?? 1,
        scaleY: (json['scaleY'] as num?)?.toDouble() ?? 1,
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      );
}
