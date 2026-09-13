/// A filled rectangle bar — a health bar, a stamina/mana meter, a boss
/// bar — drawn fresh every frame at this entity's `Position`, the same
/// "doesn't hide how it works" primitive `Text` is for HUD numbers.
/// Always screen space (a bar pinned to the viewport is the only case
/// that's come up — a world-space bar floating over an enemy's head is
/// just a `Sprite`/`Text` pair, not this): `Position.x`/`.y` are pixels
/// from the viewport's top-left, top-left corner of the bar.
///
/// [value]/[maxValue] drive the filled fraction (`value / maxValue`,
/// clamped to `[0, 1]`); nothing here updates them — a game syncs
/// `value` from wherever the real number lives (e.g. a `Health`
/// component in `engine_platformer`) each tick, the same way it would
/// update a `Text.text` string. `maxValue <= 0` renders an empty bar
/// rather than dividing by zero.
class HudBar {
  double value;
  double maxValue;
  double width;
  double height;
  int fillColorArgb;
  int backgroundColorArgb;

  /// Draw order relative to every other renderable — see `Sprite.zIndex`.
  int zIndex;

  HudBar({
    required this.value,
    required this.maxValue,
    this.width = 100,
    this.height = 12,
    this.fillColorArgb = 0xFFE0304C,
    this.backgroundColorArgb = 0x80000000,
    this.zIndex = 0,
  });

  double get fraction => maxValue <= 0 ? 0 : (value / maxValue).clamp(0, 1);

  Map<String, dynamic> toJson() => {
        'value': value,
        'maxValue': maxValue,
        'width': width,
        'height': height,
        'fillColorArgb': fillColorArgb,
        'backgroundColorArgb': backgroundColorArgb,
        'zIndex': zIndex,
      };

  factory HudBar.fromJson(Map<String, dynamic> json) => HudBar(
        value: (json['value'] as num).toDouble(),
        maxValue: (json['maxValue'] as num).toDouble(),
        width: (json['width'] as num?)?.toDouble() ?? 100,
        height: (json['height'] as num?)?.toDouble() ?? 12,
        fillColorArgb: (json['fillColorArgb'] as num?)?.toInt() ?? 0xFFE0304C,
        backgroundColorArgb: (json['backgroundColorArgb'] as num?)?.toInt() ?? 0x80000000,
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      );
}
