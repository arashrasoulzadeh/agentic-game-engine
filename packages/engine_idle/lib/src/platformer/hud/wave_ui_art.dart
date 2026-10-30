/// The generated UI art a [WaveCombatScene] can dress itself in. Every part
/// is optional: leave a stem null and that piece falls back to the plain
/// engine primitive (rectangle bars, no path, bare caption text).
class WaveUiArt {
  const WaveUiArt({
    this.barsStem,
    this.pathNodesStem,
    this.pathLineImage,
    this.captionBackdropImage,
    this.pathY = 38,
    this.pathInset = 9,
    this.pathNodeSize = 7.4,
    this.captionBackdropWidth = 142,
    this.captionBackdropHeight = 62,
  });

  /// `<stem>.png` is the `ui_bars` sheet (see `BarsArt`).
  final String? barsStem;

  /// `<stem>.png` + `.json` is the `ui_level_node` strip (locked, current,
  /// cleared, boss).
  final String? pathNodesStem;

  /// Full image stretched behind the nodes as the path line (`ui_divider`).
  final String? pathLineImage;

  /// Full image behind the caption (`ui_dialog_scroll`).
  final String? captionBackdropImage;

  /// Path height, left/right inset and node size, in world units.
  final double pathY;
  final double pathInset;
  final double pathNodeSize;

  /// Size of the caption backdrop in world units.
  final double captionBackdropWidth;
  final double captionBackdropHeight;
}
