/// A full-screen color overlay — fade to black between rooms, a red
/// damage flash, a blue-tinted underwater cutscene, a color grade for a
/// dramatic beat. `EngineView` draws one plain full-viewport rect per
/// `ScreenTint` entity, in normal (`SrcOver`) blending, on top of the
/// already-lit scene (after `ambientBrightness`/`Light2D`, so a tint
/// isn't itself darkened by the lighting pass) but below debug overlays.
///
/// [colorArgb]'s alpha channel is the tint's strength, the same
/// convention `Light2D.colorArgb` already uses — `0` alpha (fully
/// transparent) draws nothing, at no extra cost beyond the one
/// `drawRect` call. Multiple `ScreenTint` entities all draw and layer
/// naturally via alpha (each on top of the last), though the common
/// case is a single entity whose `colorArgb` a `CinematicStep`
/// (see `ScreenTintStep` in `engine_flutter`) animates over time.
class ScreenTint {
  int colorArgb;

  ScreenTint(this.colorArgb);

  Map<String, dynamic> toJson() => {'colorArgb': colorArgb};

  factory ScreenTint.fromJson(Map<String, dynamic> json) =>
      ScreenTint(json['colorArgb'] as int);
}
