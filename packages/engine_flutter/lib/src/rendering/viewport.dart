import 'dart:ui' as ui show Size, Rect, RRect;
import 'dart:ui' show Offset;

/// Defines how the game viewport should fit within the available screen space.
enum ViewportFit {
  /// Scale to fill the entire screen, potentially cropping content.
  /// Use for immersive full-screen games where edge content is non-critical.
  cover,

  /// Scale to fit entirely within the screen, adding letterbox/pillarbox bars.
  /// Use when all game content must be visible (UI, HUD, etc.).
  contain,

  /// Scale to fill width, crop height (or vice versa). Compromise between
  /// cover and contain — useful for games with flexible HUD placement.
  width,

  /// Scale to fill height, crop width. See [width].
  height,
}

/// Configuration for viewport behavior.
class ViewportConfig {
  /// Target aspect ratio (width / height) the game was designed for.
  /// The viewport will maintain this ratio within the available space.
  final double targetAspectRatio;

  /// How to fit the target aspect ratio within the screen.
  final ViewportFit fit;

  /// Minimum scale factor (prevents over-zooming on ultra-wide screens).
  final double minScale;

  /// Maximum scale factor (prevents under-zooming on very tall screens).
  final double maxScale;

  /// Whether to avoid system UI areas (notches, status bars, home indicator).
  /// When true, the viewport will be inset by safe area padding.
  final bool avoidSystemUi;

  /// Background color for letterbox/pillarbox bars.
  final int letterboxColorArgb;

  /// Whether to allow the viewport to be positioned off-center when
  /// `fit` is [ViewportFit.cover] and the aspect ratios differ significantly.
  /// When false, the viewport is centered.
  final bool centerViewport;

  const ViewportConfig({
    this.targetAspectRatio = 16 / 9,
    this.fit = ViewportFit.contain,
    this.minScale = 0.5,
    this.maxScale = 3.0,
    this.avoidSystemUi = true,
    this.letterboxColorArgb = 0xFF000000,
    this.centerViewport = true,
  });
}

/// Computed viewport layout for a given screen size.
class ViewportLayout {
  /// The rectangle (in screen pixels) where the game content should be drawn.
  final ui.Rect contentRect;

  /// The scale factor to apply to world coordinates.
  final double scale;

  /// Safe area insets (top, right, bottom, left) in screen pixels.
  final ui.RRect safeAreaInsets;

  /// Whether the viewport is letterboxed (has black bars).
  final bool isLetterboxed;

  /// Whether the viewport is pillarboxed.
  final bool isPillarboxed;

  ViewportLayout({
    required this.contentRect,
    required this.scale,
    required this.safeAreaInsets,
    required this.isLetterboxed,
    required this.isPillarboxed,
  });

  /// Transforms a world coordinate to screen coordinate within the viewport.
  Offset worldToScreen(Offset world, Offset worldOrigin, double zoom) {
    final scaledX = (world.dx - worldOrigin.dx) * zoom * scale + contentRect.left;
    final scaledY = (world.dy - worldOrigin.dy) * zoom * scale + contentRect.top;
    return Offset(scaledX, scaledY);
  }

  /// Transforms a screen coordinate to world coordinate within the viewport.
  Offset screenToWorld(Offset screen, Offset worldOrigin, double zoom) {
    final worldX = (screen.dx - contentRect.left) / (zoom * scale) + worldOrigin.dx;
    final worldY = (screen.dy - contentRect.top) / (zoom * scale) + worldOrigin.dy;
    return Offset(worldX, worldY);
  }
}

/// Computes the optimal viewport layout for a given screen size and config.
class ViewportManager {
  final ViewportConfig _config;

  ViewportManager(this._config);

  /// Computes the viewport layout for the given screen size and safe area.
  ViewportLayout computeLayout(
    ui.Size screenSize,
    ui.RRect? safeArea,
  ) {
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final _screenAspectRatio = screenWidth / screenHeight;

    // Apply safe area insets if enabled
    double effectiveWidth = screenWidth;
    double effectiveHeight = screenHeight;
    double leftInset = 0;
    double topInset = 0;
    double _rightInset = 0;
    double _bottomInset = 0;

    if (_config.avoidSystemUi && safeArea != null) {
      leftInset = safeArea.left;
      topInset = safeArea.top;
      _rightInset = screenWidth - safeArea.right;
      _bottomInset = screenHeight - safeArea.bottom;
      effectiveWidth = safeArea.width;
      effectiveHeight = safeArea.height;
    }

    final effectiveAspectRatio = effectiveWidth / effectiveHeight;
    final targetRatio = _config.targetAspectRatio;

    double scale;
    double contentWidth;
    double contentHeight;

    switch (_config.fit) {
      case ViewportFit.contain:
        // Fit entirely within screen (letterbox/pillarbox)
        if (effectiveAspectRatio > targetRatio) {
          // Screen is wider than target: pillarbox (black bars on sides)
          scale = effectiveHeight / (targetRatio * effectiveHeight);
          contentHeight = effectiveHeight;
          contentWidth = effectiveHeight * targetRatio;
        } else {
          // Screen is taller than target: letterbox (black bars on top/bottom)
          scale = effectiveWidth / (effectiveWidth / targetRatio);
          contentWidth = effectiveWidth;
          contentHeight = effectiveWidth / targetRatio;
        }
        break;

      case ViewportFit.cover:
        // Cover entire screen (crop if needed)
        if (effectiveAspectRatio > targetRatio) {
          // Screen is wider: scale to height, crop sides
          scale = effectiveHeight / (targetRatio * effectiveHeight);
          contentHeight = effectiveHeight;
          contentWidth = effectiveHeight * targetRatio;
        } else {
          // Screen is taller: scale to width, crop top/bottom
          scale = effectiveWidth / (effectiveWidth / targetRatio);
          contentWidth = effectiveWidth;
          contentHeight = effectiveWidth / targetRatio;
        }
        break;

      case ViewportFit.width:
        // Always fit width, crop height if needed
        scale = 1.0;
        contentWidth = effectiveWidth;
        contentHeight = effectiveWidth / targetRatio;
        if (contentHeight > effectiveHeight) {
          // Too tall, fall back to contain
          scale = effectiveHeight / contentHeight;
          contentHeight = effectiveHeight;
          contentWidth = effectiveHeight * targetRatio;
        }
        break;

      case ViewportFit.height:
        // Always fit height, crop width if needed
        scale = 1.0;
        contentHeight = effectiveHeight;
        contentWidth = effectiveHeight * targetRatio;
        if (contentWidth > effectiveWidth) {
          // Too wide, fall back to contain
          scale = effectiveWidth / contentWidth;
          contentWidth = effectiveWidth;
          contentHeight = effectiveWidth / targetRatio;
        }
        break;
    }

    // Clamp scale
    scale = scale.clamp(_config.minScale, _config.maxScale);
    contentWidth *= scale;
    contentHeight *= scale;

    // Position the content rect
    double contentLeft;
    double contentTop;

    if (_config.centerViewport) {
      contentLeft = leftInset + (effectiveWidth - contentWidth) / 2;
      contentTop = topInset + (effectiveHeight - contentHeight) / 2;
    } else {
      contentLeft = leftInset;
      contentTop = topInset;
    }

    final contentRect = ui.Rect.fromLTWH(
      contentLeft,
      contentTop,
      contentWidth,
      contentHeight,
    );

    // Build safe area insets RRect
    final safeAreaInsets = _config.avoidSystemUi && safeArea != null
        ? safeArea
        : ui.RRect.fromRectXY(
            ui.Rect.fromLTWH(0, 0, screenWidth, screenHeight),
            0,
            0,
          );

    final isLetterboxed = contentHeight < effectiveHeight - 1;
    final isPillarboxed = contentWidth < effectiveWidth - 1;

    return ViewportLayout(
      contentRect: contentRect,
      scale: scale,
      safeAreaInsets: safeAreaInsets,
      isLetterboxed: isLetterboxed,
      isPillarboxed: isPillarboxed,
    );
  }
}