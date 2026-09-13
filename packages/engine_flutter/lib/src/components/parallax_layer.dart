/// A background image (an atlas region, same as `Sprite`) that
/// scrolls at a fraction of the camera's movement instead of moving
/// 1:1 with it — the classic layered-background effect (distant
/// mountains barely move, near clouds move more, the actual level
/// moves fully). `EngineView` draws every `ParallaxLayer` first, behind
/// tiles and sprites.
///
/// [scrollFactorX]/[scrollFactorY] are the fraction of camera movement
/// this layer tracks: `0` means fixed to the screen regardless of
/// camera position (e.g. a static sky), `1` means it scrolls exactly
/// like normal world content, and anything in between (the common
/// case, e.g. `0.3`) reads as "further away." The entity's own
/// `Position` is this layer's base offset — usually `Position(0, 0)`,
/// but useful for stacking several layers of the same image at
/// different vertical offsets.
///
/// [tileX]/[tileY] repeat the region across the full viewport on that
/// axis, so a single background strip covers arbitrarily wide/tall
/// scrolling without the game needing to author a world-sized image.
/// Leave one (or both) off for a layer meant to appear once (e.g. a
/// fixed logo/vignette) rather than tiled.
class ParallaxLayer {
  String atlasId;
  String region;
  double scrollFactorX;
  double scrollFactorY;
  bool tileX;
  bool tileY;

  ParallaxLayer(
    this.atlasId,
    this.region, {
    this.scrollFactorX = 0.5,
    this.scrollFactorY = 0,
    this.tileX = true,
    this.tileY = false,
  });

  Map<String, dynamic> toJson() => {
        'atlasId': atlasId,
        'region': region,
        'scrollFactorX': scrollFactorX,
        'scrollFactorY': scrollFactorY,
        'tileX': tileX,
        'tileY': tileY,
      };

  factory ParallaxLayer.fromJson(Map<String, dynamic> json) => ParallaxLayer(
        json['atlasId'] as String,
        json['region'] as String,
        scrollFactorX: (json['scrollFactorX'] as num?)?.toDouble() ?? 0.5,
        scrollFactorY: (json['scrollFactorY'] as num?)?.toDouble() ?? 0,
        tileX: json['tileX'] as bool? ?? true,
        tileY: json['tileY'] as bool? ?? false,
      );
}
