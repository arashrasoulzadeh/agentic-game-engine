/// `reveal` shows the scene only where at least one `reveal`-mode
/// `ClipShape` covers it (everything else is clipped away entirely, not
/// just darkened) — a hard-edged spotlight/peephole, or a growing/
/// shrinking wipe transition between scenes. `cutout` does the
/// opposite: punches a hole through the already-drawn scene wherever
/// it covers, showing nothing there (not even the background color) —
/// a vignette is a `cutout` shape sized to the screen's edges with the
/// visible area left uncovered in the middle.
enum ClipShapeMode { reveal, cutout }

/// A masking/clipping primitive `EngineView`'s z-index draw ordering
/// alone can't express — z-index only reorders whole draw *calls*, it
/// has no way to say "this shape cuts a hole in what's behind it" or
/// "only show the scene through this shape." Circle or rectangle,
/// centered on this entity's own `Position`. See `ClipShapeMode` for
/// what `reveal`/`cutout` each actually do, and `EngineView`'s own
/// rendering doc comment for *how* (a real Flutter `Canvas` is
/// immediate-mode, so "reveal" has to *clip drawing as it happens*
/// while "cutout" has to *erase already-drawn pixels* — genuinely
/// different mechanisms, not two modes of the same one).
class ClipShape {
  /// `true` (default): a circle, [radius] wide. `false`: a rectangle,
  /// [width]x[height], centered on `Position` — [radius] is ignored
  /// then, and vice versa, rather than needing two separate component
  /// types for what's otherwise identical (mode/softness) handling.
  bool isCircle;

  double radius;
  double width;
  double height;

  ClipShapeMode mode;

  /// Blur radius (logical pixels, pre-`Camera.zoom`) softening this
  /// shape's edge — `0` (default) is a hard, unblurred cutoff. Same
  /// convention as `Light2D.shadowEdgeSoftness`.
  double softness;

  ClipShape({
    this.isCircle = true,
    this.radius = 100,
    this.width = 200,
    this.height = 200,
    this.mode = ClipShapeMode.reveal,
    this.softness = 0,
  });

  Map<String, dynamic> toJson() => {
        'isCircle': isCircle,
        'radius': radius,
        'width': width,
        'height': height,
        'mode': mode.name,
        'softness': softness,
      };

  factory ClipShape.fromJson(Map<String, dynamic> json) => ClipShape(
        isCircle: json['isCircle'] as bool? ?? true,
        radius: (json['radius'] as num?)?.toDouble() ?? 100,
        width: (json['width'] as num?)?.toDouble() ?? 200,
        height: (json['height'] as num?)?.toDouble() ?? 200,
        mode: ClipShapeMode.values.firstWhere(
          (m) => m.name == json['mode'],
          orElse: () => ClipShapeMode.reveal,
        ),
        softness: (json['softness'] as num?)?.toDouble() ?? 0,
      );
}
