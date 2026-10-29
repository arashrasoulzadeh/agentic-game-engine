import 'dart:ui' as ui show Size, Rect, RRect;
import 'dart:ui' show Offset;

/// How the game's drawing area fits a screen whose shape differs from the one the game was designed
/// for.
enum ViewportFit {
  /// The largest area of the target aspect ratio that fits inside the screen. Nothing is cropped;
  /// the spare space becomes bars (letterbox above and below, pillarbox at the sides).
  contain,

  /// The smallest area of the target aspect ratio that covers the whole screen. Nothing is empty;
  /// whatever sticks out past the screen is cropped.
  cover,

  /// Always as wide as the screen. If that makes it taller than the screen it is cropped
  /// vertically; if shorter, there are bars above and below.
  width,

  /// Always as tall as the screen; the width follows, with bars or cropping at the sides.
  height,
}

/// Where the game is drawn on screens of any shape.
///
/// This decides the **rectangle** the game occupies (its aspect ratio, the bars around it, the
/// system safe area). By itself it does not scale the world: one world unit is still `Camera.zoom`
/// pixels, so on a larger screen you see more of the world, not a bigger picture. Set
/// [ViewportConfig.fitWorld] for a fixed field of view instead.
class ViewportConfig {
  /// Width divided by height of the game's drawing area.
  final double targetAspectRatio;

  final ViewportFit fit;

  /// Keep the game inside the system's safe area (notches, status and navigation bars).
  final bool avoidSystemUi;

  /// Colour of the bars, as ARGB.
  final int letterboxColorArgb;

  /// Centre the area in the available space (true), or pin it to the top left.
  final bool centerViewport;

  /// Scale the picture to the rectangle: every frame the engine sets `Camera.zoom` so the whole
  /// world width fills it. For a world authored at a fixed logical size (a 180x320 portrait game)
  /// this replaces computing a zoom per screen by hand. Pair it with a [targetAspectRatio] equal
  /// to the world's width / height so nothing is cropped.
  final bool fitWorld;

  const ViewportConfig({
    this.targetAspectRatio = 16 / 9,
    this.fit = ViewportFit.contain,
    this.avoidSystemUi = true,
    this.letterboxColorArgb = 0xFF000000,
    this.centerViewport = true,
    this.fitWorld = false,
  }) : assert(targetAspectRatio > 0, 'targetAspectRatio must be positive');
}

/// The result of laying the game out on a particular screen.
class ViewportLayout {
  /// Where the game is drawn, in screen coordinates. With [ViewportFit.cover] (and `width`/`height`
  /// when they overshoot) it can extend past the screen; the overflow is cropped.
  final ui.Rect contentRect;

  /// The screen region the game was allowed to use (the whole screen, or the safe area).
  final ui.RRect safeAreaInsets;

  /// True when there are bars above and below the game.
  final bool isLetterboxed;

  /// True when there are bars to the left and right of the game.
  final bool isPillarboxed;

  const ViewportLayout({
    required this.contentRect,
    required this.safeAreaInsets,
    required this.isLetterboxed,
    required this.isPillarboxed,
  });

  /// A point in the game's own coordinates (origin at the top left of the drawn area) for a point
  /// on the screen.
  Offset screenToContent(Offset screen) => screen - contentRect.topLeft;

  /// The reverse of [screenToContent].
  Offset contentToScreen(Offset content) => content + contentRect.topLeft;
}

/// Computes [ViewportLayout]s for a [ViewportConfig].
class ViewportManager {
  final ViewportConfig _config;

  ViewportManager(this._config);

  /// Lays the game out on a screen of [screenSize]. [safeArea] is the usable region (from
  /// `MediaQuery.padding`); it is only honoured when the config has `avoidSystemUi`.
  ViewportLayout computeLayout(ui.Size screenSize, ui.RRect? safeArea) {
    final useSafe = _config.avoidSystemUi && safeArea != null;
    final areaLeft = useSafe ? safeArea.left : 0.0;
    final areaTop = useSafe ? safeArea.top : 0.0;
    final areaWidth = useSafe ? safeArea.width : screenSize.width;
    final areaHeight = useSafe ? safeArea.height : screenSize.height;
    final ratio = _config.targetAspectRatio;

    double width;
    double height;
    switch (_config.fit) {
      case ViewportFit.contain:
        if (areaWidth / areaHeight > ratio) {
          height = areaHeight;
          width = height * ratio;
        } else {
          width = areaWidth;
          height = width / ratio;
        }
      case ViewportFit.cover:
        if (areaWidth / areaHeight > ratio) {
          width = areaWidth;
          height = width / ratio;
        } else {
          height = areaHeight;
          width = height * ratio;
        }
      case ViewportFit.width:
        width = areaWidth;
        height = width / ratio;
      case ViewportFit.height:
        height = areaHeight;
        width = height * ratio;
    }

    final left = _config.centerViewport
        ? areaLeft + (areaWidth - width) / 2
        : areaLeft;
    final top = _config.centerViewport
        ? areaTop + (areaHeight - height) / 2
        : areaTop;

    return ViewportLayout(
      contentRect: ui.Rect.fromLTWH(left, top, width, height),
      safeAreaInsets: useSafe
          ? safeArea
          : ui.RRect.fromRectXY(
              ui.Rect.fromLTWH(0, 0, screenSize.width, screenSize.height),
              0,
              0,
            ),
      isLetterboxed: height < areaHeight - 1,
      isPillarboxed: width < areaWidth - 1,
    );
  }
}
