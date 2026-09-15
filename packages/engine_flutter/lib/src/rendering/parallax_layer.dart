/// A background image (an atlas region, same as `Sprite`) that
/// scrolls at a fraction of the camera's movement instead of moving
/// 1:1 with it — the classic layered-background effect (distant
/// mountains barely move, near clouds move more, the actual level
/// moves fully). `EngineView` draws every `ParallaxLayer` first by
/// default (behind tiles/sprites/particles) — see [zIndex] to change
/// that.
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
/// fixed logo/vignette) rather than tiled. Tiling only looks right for
/// art actually authored as a seamless repeatable strip (a tileable
/// ground/sky texture) — repeating a single painted vista (a full
/// scene with its own sky-to-ground composition, e.g. cropped concept
/// art) stacks duplicate copies of that whole scene, which reads as
/// broken, not as "more of the same." For that kind of one-off vista
/// art, use [fitHeight] instead of [tileY].
///
/// [fitHeight] stretches the region to exactly the viewport's height
/// (ignoring its native pixel height and [scrollFactorY]/the entity's
/// `Position.y`, forcing the top edge to the very top of the screen)
/// instead of drawing it at native size — guarantees full vertical
/// coverage regardless of window size for art that can't be tiled,
/// at the cost of a non-uniform stretch (aspect ratio isn't
/// preserved). [tileX]/[scrollFactorX] still apply normally on the
/// horizontal axis, since a vista's sideways repetition (e.g. more
/// pillars extending into the distance) usually reads fine even when
/// its vertical sky-to-ground composition can't.
class ParallaxLayer {
  String atlasId;
  String region;
  double scrollFactorX;
  double scrollFactorY;
  bool tileX;
  bool tileY;
  bool fitHeight;

  /// Draw order relative to every other renderable — see `Sprite.zIndex`
  /// for the full rule. Left at the default (0, tying with everything
  /// else), a `ParallaxLayer` still draws behind tiles/sprites/particles
  /// because of the engine's original-order tie-break, so most games
  /// never need to touch this.
  int zIndex;

  ParallaxLayer(
    this.atlasId,
    this.region, {
    this.scrollFactorX = 0.5,
    this.scrollFactorY = 0,
    this.tileX = true,
    this.tileY = false,
    this.fitHeight = false,
    this.zIndex = 0,
  });

  Map<String, dynamic> toJson() => {
        'atlasId': atlasId,
        'region': region,
        'scrollFactorX': scrollFactorX,
        'scrollFactorY': scrollFactorY,
        'tileX': tileX,
        'tileY': tileY,
        'fitHeight': fitHeight,
        'zIndex': zIndex,
      };

  factory ParallaxLayer.fromJson(Map<String, dynamic> json) => ParallaxLayer(
        json['atlasId'] as String,
        json['region'] as String,
        scrollFactorX: (json['scrollFactorX'] as num?)?.toDouble() ?? 0.5,
        scrollFactorY: (json['scrollFactorY'] as num?)?.toDouble() ?? 0,
        tileX: json['tileX'] as bool? ?? true,
        tileY: json['tileY'] as bool? ?? false,
        fitHeight: json['fitHeight'] as bool? ?? false,
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      );
}
