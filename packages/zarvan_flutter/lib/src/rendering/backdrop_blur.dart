/// Blurs everything drawn *below* [belowZIndex] while whatever sits at or
/// above it stays sharp: a dialog over a blurred, paused game.
///
/// `EngineView` draws the lower z-bands into one layer filtered by a Gaussian
/// blur of [sigma] world units (scaled by the camera zoom), then the rest on
/// top as usual. One entity carries it; the first with a [sigma] above zero
/// wins, and `0` costs nothing. Animate [sigma] to fade the blur in and out.
/// It applies in the normal draw path; a scene that uses ambient lighting
/// (`ambientBrightness` below 1) draws without it.
class BackdropBlur {
  /// Blur radius in world units; `0` is off.
  double sigma;

  /// Items with a `zIndex` below this are blurred, the rest are not.
  int belowZIndex;

  BackdropBlur({this.sigma = 0, required this.belowZIndex});

  Map<String, dynamic> toJson() => {'sigma': sigma, 'belowZIndex': belowZIndex};

  factory BackdropBlur.fromJson(Map<String, dynamic> json) => BackdropBlur(
    sigma: (json['sigma'] as num?)?.toDouble() ?? 0,
    belowZIndex: (json['belowZIndex'] as num).toInt(),
  );
}
