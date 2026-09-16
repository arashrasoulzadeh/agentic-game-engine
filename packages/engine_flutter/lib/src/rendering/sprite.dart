/// Data-only sprite reference: which atlas, which named region, and a
/// simple transform. Resolved against an `AtlasRegistry` at render time,
/// which keeps this component plain-JSON serializable for agent authoring.
///
/// [screenSpace] mirrors `Text.screenSpace`: `false` (default) is world
/// space — `Position` scrolls/zooms with the `Camera`, the original
/// behavior. `true` is screen space — `Position.x`/`.y` are viewport
/// pixels from the top-left, unaffected by camera pan/zoom, `scaleX`/
/// `scaleY` applied at native pixel size (not multiplied by
/// `camera.zoom`). Added for UI decoration (menu frames, dividers,
/// icons) that needs to sit at a fixed spot on screen regardless of
/// camera state — before this, a screen-space-looking layout (like
/// `ButtonMenuScene`'s buttons) could only get there by relying on
/// `Position` values that happen to line up with the camera's own
/// transform (documented, and fragile, in more than one call site) or
/// mixing in `NineSliceSprite` (always screen space, but its 9-slice
/// stretching isn't right for a small fixed-size icon). Same anchoring
/// as world-space `Sprite`: `Position` is the drawn image's center.
class Sprite {
  String atlasId;
  String region;
  double rotation;
  double scaleX;
  double scaleY;
  bool screenSpace;

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
    this.screenSpace = false,
    this.zIndex = 0,
  });

  Map<String, dynamic> toJson() => {
        'atlasId': atlasId,
        'region': region,
        'rotation': rotation,
        'scaleX': scaleX,
        'scaleY': scaleY,
        'screenSpace': screenSpace,
        'zIndex': zIndex,
      };

  factory Sprite.fromJson(Map<String, dynamic> json) => Sprite(
        json['atlasId'] as String,
        json['region'] as String,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        scaleX: (json['scaleX'] as num?)?.toDouble() ?? 1,
        scaleY: (json['scaleY'] as num?)?.toDouble() ?? 1,
        screenSpace: json['screenSpace'] as bool? ?? false,
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      );
}
