/// Horizontal alignment of a `Text` component around its entity's
/// `Position` — which edge/center of the drawn text sits at that point.
enum TextAlignment { left, center, right }

/// A piece of text drawn fresh every frame at this entity's `Position`
/// — the "doesn't hide how it works" text-rendering primitive: for a
/// small, fixed set of strings known ahead of time (menu buttons),
/// baking them once into a `Sprite` atlas (`buildMenuButtonAtlas`) is
/// cheaper and is what `ButtonMenuScene` already does; for anything
/// that changes at runtime — a damage number, a dialogue line, a score
/// readout, an NPC name — this is that missing piece: attach `Text`,
/// `EngineView` draws it via `TextPainter` every tick.
///
/// [screenSpace] chooses which coordinate system `Position` is in:
/// `false` (default) is world space — the text scrolls/zooms with the
/// `Camera`, e.g. a damage number floating over an enemy's head;
/// `true` is screen space — `Position.x`/`.y` are pixels from the
/// viewport's top-left, ignoring the camera entirely, e.g. a HUD score
/// display that should stay in the same spot on screen no matter where
/// the camera is looking.
///
/// [maxWidth] enables wrapping: `null` (default) is today's original
/// single-line-however-long-it-is behavior; a finite value wraps onto
/// as many lines as needed to stay within it (Flutter's own
/// `TextPainter` handles the actual line-breaking — `EngineView` just
/// passes `maxWidth` through to `layout`), for a dialogue box or a
/// long HUD message that shouldn't run off-screen. In world space it's
/// in world units and scales with `Camera.zoom` the same way
/// `fontSize` does, so the wrap point stays visually consistent at any
/// zoom level; in screen space it's viewport pixels, unscaled.
class Text {
  String text;
  double fontSize;
  int colorArgb;
  TextAlignment align;
  bool screenSpace;
  double? maxWidth;

  /// Draw order relative to every other renderable — see
  /// `engine_flutter`'s `Sprite.zIndex` for the full tie-break rule.
  /// Screen-space HUD text typically wants a high `zIndex` so it draws
  /// above world content regardless of that content's own `zIndex`.
  int zIndex;

  Text(
    this.text, {
    this.fontSize = 16,
    this.colorArgb = 0xFFFFFFFF,
    this.align = TextAlignment.center,
    this.screenSpace = false,
    this.zIndex = 0,
    this.maxWidth,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'fontSize': fontSize,
        'colorArgb': colorArgb,
        'align': align.name,
        'screenSpace': screenSpace,
        'zIndex': zIndex,
        if (maxWidth != null) 'maxWidth': maxWidth,
      };

  factory Text.fromJson(Map<String, dynamic> json) => Text(
        json['text'] as String,
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 16,
        colorArgb: (json['colorArgb'] as num?)?.toInt() ?? 0xFFFFFFFF,
        align: TextAlignment.values.firstWhere(
          (a) => a.name == json['align'],
          orElse: () => TextAlignment.center,
        ),
        screenSpace: json['screenSpace'] as bool? ?? false,
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
        maxWidth: (json['maxWidth'] as num?)?.toDouble(),
      );
}
