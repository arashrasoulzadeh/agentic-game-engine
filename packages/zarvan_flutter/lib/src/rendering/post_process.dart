import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// One full-screen pass applied over a rendered scene by [PostProcessed].
///
/// Passes are plain data so a game can swap a stack at runtime (a damage
/// vignette, a CRT mode in settings) without touching the renderer.
sealed class PostEffect {
  const PostEffect();
}

/// Brightness, contrast and saturation grading, folded into one colour matrix.
///
/// 1 is neutral for all three. [tint] multiplies the result (white = none).
class ColorGrade extends PostEffect {
  /// Creates a grade; the defaults are neutral.
  const ColorGrade({
    this.brightness = 1,
    this.contrast = 1,
    this.saturation = 1,
    this.tint = const Color(0xFFFFFFFF),
  });

  /// Multiplier on every channel.
  final double brightness;

  /// Scale around mid-grey; below 1 flattens, above 1 punches.
  final double contrast;

  /// 0 is greyscale, 1 unchanged, above 1 oversaturated.
  final double saturation;

  /// Multiplied into the picture for a warm/cold wash.
  final Color tint;

  /// The 4x5 matrix (the shape `ColorFilter.matrix` takes) for this grade.
  List<double> toMatrix() {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final s = saturation;
    final sat = <double>[
      lr * (1 - s) + s,
      lg * (1 - s),
      lb * (1 - s),
      lr * (1 - s),
      lg * (1 - s) + s,
      lb * (1 - s),
      lr * (1 - s),
      lg * (1 - s),
      lb * (1 - s) + s,
    ];
    final tr = (tint.r), tg = (tint.g), tb = (tint.b);
    final k = brightness * contrast;
    final offset = 255 * 0.5 * (1 - contrast) * brightness;
    final tints = [tr, tg, tb];
    final out = <double>[];
    for (var row = 0; row < 3; row++) {
      final m = tints[row] * k;
      out
        ..add(sat[row * 3] * m)
        ..add(sat[row * 3 + 1] * m)
        ..add(sat[row * 3 + 2] * m)
        ..add(0)
        ..add(offset * tints[row]);
    }
    return [...out, 0, 0, 0, 1, 0];
  }
}

/// Darkens the screen edges; [strength] is the edge opacity in 0..1 and
/// [radius] how far from the centre (as a fraction of the half-diagonal)
/// the darkening starts.
class Vignette extends PostEffect {
  /// Creates a vignette.
  const Vignette({
    this.strength = 0.5,
    this.radius = 0.55,
    this.color = const Color(0xFF000000),
  });

  /// Edge opacity, 0..1.
  final double strength;

  /// Where the fade begins, 0 (centre) to 1 (corner).
  final double radius;

  /// Colour fading in at the edges.
  final Color color;
}

/// Horizontal CRT scanlines: every [spacing] pixels a line of [opacity] black.
class Scanlines extends PostEffect {
  /// Creates scanlines.
  const Scanlines({this.spacing = 3, this.opacity = 0.18});

  /// Pixels between line starts (at least 2 is sensible).
  final double spacing;

  /// Darkness of each line, 0..1.
  final double opacity;
}

/// Wraps [child] in the colour passes of [effects] and paints overlay passes
/// (vignette, scanlines) on top, in list order.
///
/// Colour grades compose into one `ColorFilter` layer, so a stack costs one
/// extra layer however many grades it holds. Overlay passes are single
/// full-screen draws. Shader-based passes (bloom, chromatic aberration,
/// pixelate) are not here: they need fragment programs this package does
/// not ship yet.
class PostProcessed extends StatelessWidget {
  /// Creates the wrapper.
  const PostProcessed({super.key, required this.effects, required this.child});

  /// The pass stack, applied in order.
  final List<PostEffect> effects;

  /// The rendered scene.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    var out = child;
    final grades = effects.whereType<ColorGrade>().toList();
    if (grades.isNotEmpty) {
      out = ColorFiltered(
        colorFilter: ColorFilter.matrix(composeGrades(grades)),
        child: out,
      );
    }
    final overlays = [
      for (final e in effects)
        if (e is! ColorGrade) e,
    ];
    if (overlays.isEmpty) return out;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        out,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _OverlayPainter(overlays)),
          ),
        ),
      ],
    );
  }
}

/// Multiplies [grades] into one 4x5 colour matrix, first grade applied first.
List<double> composeGrades(List<ColorGrade> grades) {
  var acc = ColorGrade().toMatrix();
  for (final g in grades) {
    acc = _mul(g.toMatrix(), acc);
  }
  return acc;
}

List<double> _mul(List<double> b, List<double> a) {
  final r = List<double>.filled(20, 0);
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 5; j++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += b[i * 5 + k] * a[k * 5 + j];
      }
      if (j == 4) v += b[i * 5 + 4];
      r[i * 5 + j] = v;
    }
  }
  return r;
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.effects);
  final List<PostEffect> effects;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    for (final e in effects) {
      switch (e) {
        case Vignette():
          final r = size.shortestSide > 0
              ? math.sqrt(size.width * size.width + size.height * size.height) /
                    2
              : 1.0;
          canvas.drawRect(
            rect,
            Paint()
              ..shader = RadialGradient(
                radius: 1,
                colors: [
                  e.color.withValues(alpha: 0),
                  e.color.withValues(alpha: 0),
                  e.color.withValues(alpha: e.strength.clamp(0, 1)),
                ],
                stops: [0, e.radius.clamp(0, 0.99), 1],
              ).createShader(Rect.fromCircle(center: rect.center, radius: r)),
          );
        case Scanlines():
          final p = Paint()
            ..color = Color.fromRGBO(0, 0, 0, e.opacity.clamp(0, 1));
          for (var y = 0.0; y < size.height; y += e.spacing) {
            canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
          }
        case ColorGrade():
          break;
      }
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => true;
}
