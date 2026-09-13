/// A resizable UI panel/dialog-box background drawn from one atlas
/// region split into a 3x3 grid by [insetLeft]/[insetTop]/[insetRight]/
/// [insetBottom] (all in source-image pixels, measured in from each
/// edge of the region) — the four corners are drawn at their native
/// size, the four edges stretch along one axis to fill the gap between
/// corners, and the center stretches both axes. This is what makes a
/// panel resizable to any [width]/[height] without its corners/border
/// art stretching into mush the way a plain scaled `Sprite` would.
///
/// Always screen space — `Position.x`/`.y` are the top-left corner in
/// viewport pixels, ignoring the camera entirely, same reasoning as
/// `HudBar`: a resizable panel pinned to the viewport (a dialog box, an
/// inventory background) is the case that's actually come up; a
/// world-space stretched panel would need insets that also scale with
/// `Camera.zoom`, which nothing has asked for yet.
///
/// Not batched via `Canvas.drawAtlas` the way plain `Sprite`s are —
/// nine independently-scaled sub-rects per instance isn't what
/// `drawAtlas`'s single-transform-per-sprite model supports — same
/// "drawn individually, not batched" tradeoff `Text`/`HudBar` already
/// make.
class NineSliceSprite {
  String atlasId;
  String region;
  double width;
  double height;
  double insetLeft;
  double insetTop;
  double insetRight;
  double insetBottom;

  /// Draw order relative to every other renderable — see `Sprite.zIndex`.
  int zIndex;

  NineSliceSprite(
    this.atlasId,
    this.region, {
    required this.width,
    required this.height,
    required this.insetLeft,
    required this.insetTop,
    required this.insetRight,
    required this.insetBottom,
    this.zIndex = 0,
  });

  Map<String, dynamic> toJson() => {
        'atlasId': atlasId,
        'region': region,
        'width': width,
        'height': height,
        'insetLeft': insetLeft,
        'insetTop': insetTop,
        'insetRight': insetRight,
        'insetBottom': insetBottom,
        'zIndex': zIndex,
      };

  factory NineSliceSprite.fromJson(Map<String, dynamic> json) => NineSliceSprite(
        json['atlasId'] as String,
        json['region'] as String,
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        insetLeft: (json['insetLeft'] as num).toDouble(),
        insetTop: (json['insetTop'] as num).toDouble(),
        insetRight: (json['insetRight'] as num).toDouble(),
        insetBottom: (json['insetBottom'] as num).toDouble(),
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      );
}
