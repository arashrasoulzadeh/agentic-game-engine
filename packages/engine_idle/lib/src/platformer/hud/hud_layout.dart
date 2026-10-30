/// One screen-space label of the wave-combat HUD.
class HudTextStyle {
  const HudTextStyle({
    required this.x,
    required this.y,
    this.fontSize = 9,
    this.colorArgb = 0xFFFFFFFF,
    this.maxWidth = 170,
    this.rtl,
  });

  /// Centre of the label, in screen-space world units.
  final double x;
  final double y;
  final double fontSize;
  final int colorArgb;
  final double maxWidth;

  /// Forces right-to-left layout (`Text.rtl`); null follows the locale.
  final bool? rtl;
}

/// One health bar of the wave-combat HUD.
class HudBarStyle {
  const HudBarStyle({
    required this.x,
    required this.y,
    this.width = 148,
    this.height = 10,
    required this.fillColorArgb,
  });

  /// Top-left corner, in screen-space world units.
  final double x;
  final double y;
  final double width;
  final double height;
  final int fillColorArgb;
}

/// Where the wave-combat HUD sits and how it looks: the defaults suit a
/// 180x320 portrait world with the hero's bar on top and the enemy's below
/// it. Replace any part for another layout, size or palette.
class HudLayout {
  const HudLayout({
    this.status = const HudTextStyle(
      x: 90,
      y: 14,
      fontSize: 11,
      colorArgb: 0xFFFFE7A0,
    ),
    this.enemy = const HudTextStyle(x: 90, y: 44, colorArgb: 0xFFFFCCBC),
    this.description = const HudTextStyle(
      x: 90,
      y: 160,
      fontSize: 7.5,
      colorArgb: 0xFFFFF3D0,
      maxWidth: 150,
      rtl: true,
    ),
    this.heroBar = const HudBarStyle(x: 16, y: 28, fillColorArgb: 0xFF2AA198),
    this.enemyBar = const HudBarStyle(x: 16, y: 52, fillColorArgb: 0xFFE0304C),
    this.bossBarColorArgb = 0xFFE65100,
  });

  final HudTextStyle status;
  final HudTextStyle enemy;

  /// The enemy's description, typed in at the centre of the world by a
  /// `DialogueCaption` while the enemy approaches. Unlike the other labels,
  /// which are in screen pixels, its `x`, `y`, `fontSize` and `maxWidth` are
  /// world units (so it scales with the window).
  final HudTextStyle description;
  final HudBarStyle heroBar;
  final HudBarStyle enemyBar;

  /// Fill of the enemy bar during the boss encounter.
  final int bossBarColorArgb;
}
