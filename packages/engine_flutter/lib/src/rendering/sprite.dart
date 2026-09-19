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

  /// Extra offset — in unscaled atlas pixels, the same units as the
  /// current region's own width/height — added to `Position` before
  /// drawing. `0` (the default) is unchanged behavior: the region
  /// draws centered exactly on `Position`, like every `Sprite` before
  /// these fields existed.
  ///
  /// Exists for `AnimationSystem` to write per-frame (see
  /// `AnimationClip.frameOffsetsY`'s doc comment for the motivating
  /// case: frames of different pixel heights across one animated
  /// character, which center-anchoring alone makes visibly bob up and
  /// down between clips), but nothing stops a game from setting it
  /// directly on a static `Sprite` too — e.g. nudging one prop's art
  /// to line up with its `Position` without needing a second, offset
  /// entity.
  ///
  /// Scaled by [scaleX]/[scaleY] and, for a world-space `Sprite`
  /// (`screenSpace: false`), by `Camera.zoom` — the same transform
  /// `Position` itself goes through — so the offset stays visually
  /// consistent at any zoom level. Not rotated by [rotation]: for the
  /// walking/attacking/dying character animations this exists for,
  /// rotation is always 0, so this keeps the common case simple rather
  /// than adding trig noise for a case nothing here actually needs yet.
  double offsetX;
  double offsetY;

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
    this.offsetX = 0,
    this.offsetY = 0,
    this.zIndex = 0,
  });

  Map<String, dynamic> toJson() => {
        'atlasId': atlasId,
        'region': region,
        'rotation': rotation,
        'scaleX': scaleX,
        'scaleY': scaleY,
        'screenSpace': screenSpace,
        'offsetX': offsetX,
        'offsetY': offsetY,
        'zIndex': zIndex,
      };

  factory Sprite.fromJson(Map<String, dynamic> json) => Sprite(
        json['atlasId'] as String,
        json['region'] as String,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        scaleX: (json['scaleX'] as num?)?.toDouble() ?? 1,
        scaleY: (json['scaleY'] as num?)?.toDouble() ?? 1,
        screenSpace: json['screenSpace'] as bool? ?? false,
        offsetX: (json['offsetX'] as num?)?.toDouble() ?? 0,
        offsetY: (json['offsetY'] as num?)?.toDouble() ?? 0,
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      );
}
