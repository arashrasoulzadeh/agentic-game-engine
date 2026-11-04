import 'upgrade_bar.dart';

/// The generated UI art a [WaveCombatScene] can dress itself in. Every part
/// is optional: leave a stem null and that piece falls back to the plain
/// engine primitive (rectangle bars, no path, bare caption text).
class WaveUiArt {
  const WaveUiArt({
    this.barsStem,
    this.pathNodesStem,
    this.pathLineImage,
    this.buttonImage,
    this.iconsStem,
    this.upgradeLayout = const UpgradeLayout(),
    this.captionBackdropImage,
    this.panelImage,
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

  /// Full path of the `ui_button_atlas` sheet (see `ButtonSheet`). Needed for
  /// the upgrade and retry buttons; without it a lost run replays on any tap.
  final String? buttonImage;

  /// `<stem>.png` + `.json` is a strip of square icons; `HeroUpgrade.icon` and
  /// `HeroSkill.icon` pick a frame to draw on the left of their button.
  final String? iconsStem;

  /// Where the upgrade buttons, coin counter and retry button sit.
  final UpgradeLayout upgradeLayout;

  /// Full image behind the caption (`ui_dialog_scroll`).
  final String? captionBackdropImage;

  /// Full image of a framed panel (`ui_panel_9slice`): the border of
  /// `UpgradeLayout.frameInset` pixels is kept, the middle stretches. Draws
  /// the upgrades dialog (`UpgradeLayout.menu`); without it the dialog is bare.
  final String? panelImage;

  /// Path height, left/right inset and node size, in world units.
  final double pathY;
  final double pathInset;
  final double pathNodeSize;

  /// Size of the caption backdrop in world units.
  final double captionBackdropWidth;
  final double captionBackdropHeight;
}
