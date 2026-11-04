import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Strengths for the one-pass post-processing shader (`shaders/post_fx.frag`).
///
/// Every field at its default is off, so a game sets only what it wants. The
/// presets give a starting look; tune from there.
class ShaderPostFx {
  /// Creates a parameter set; all effects are off by default.
  const ShaderPostFx({
    this.bloom = 0,
    this.bloomThreshold = 0.6,
    this.bloomRadius = 10,
    this.chromaticAberration = 0,
    this.pixelSize = 0,
    this.scanlines = 0,
    this.scanlineSpacing = 3,
    this.curvature = 0,
    this.phosphorMask = 0,
    this.vignette = 0,
    this.grain = 0,
  });

  /// A soft glow on bright areas.
  const ShaderPostFx.bloomOnly({double intensity = 0.5})
    : this(bloom: intensity);

  /// Curved screen, scanlines, phosphor mask, vignette, a little bloom.
  const ShaderPostFx.crt()
    : this(
        bloom: 0.25,
        scanlines: 0.35,
        curvature: 0.6,
        phosphorMask: 0.15,
        vignette: 0.45,
        chromaticAberration: 1.2,
        grain: 0.03,
      );

  /// Added back on top: brightness of the blurred bright-pass (0 = off).
  final double bloom;

  /// Luminance (0..1) above which pixels glow.
  final double bloomThreshold;

  /// Blur reach in pixels.
  final double bloomRadius;

  /// Red/blue channel split in pixels at the screen edge.
  final double chromaticAberration;

  /// Edge length in pixels of each big pixel (0 = off).
  final double pixelSize;

  /// Scanline darkness 0..1.
  final double scanlines;

  /// Pixels per scanline period.
  final double scanlineSpacing;

  /// Barrel distortion; 0 flat.
  final double curvature;

  /// RGB stripe darkness 0..1.
  final double phosphorMask;

  /// Edge darkening 0..1.
  final double vignette;

  /// Animated noise amplitude.
  final double grain;

  /// Whether every effect is off.
  bool get isIdentity =>
      bloom == 0 &&
      chromaticAberration == 0 &&
      pixelSize == 0 &&
      scanlines == 0 &&
      curvature == 0 &&
      phosphorMask == 0 &&
      vignette == 0 &&
      grain == 0;

  /// The shader's float uniforms after `uSize` (12 values, `uA`..`uC`).
  List<double> toUniforms(double time) => [
    bloom, bloomThreshold, bloomRadius, chromaticAberration, //
    pixelSize, scanlines, curvature, vignette,
    time, grain, phosphorMask, scanlineSpacing,
  ];
}

/// Runs [child] through `shaders/post_fx.frag`: bloom, chromatic aberration,
/// pixelate, CRT and friends in one pass.
///
/// Works on every Flutter backend by snapshotting [child] each frame
/// (`RepaintBoundary.toImage`) and redrawing the snapshot through the shader,
/// so the picture is one frame behind and costs a render-to-image per frame:
/// use [scale] below 1 to trade sharpness for speed. If the shader cannot be
/// loaded, or [fx] is the identity, [child] is shown unchanged.
class ShaderPostProcessed extends StatefulWidget {
  /// Creates the wrapper.
  const ShaderPostProcessed({
    super.key,
    required this.fx,
    required this.child,
    this.scale = 1,
  });

  /// The effect strengths; change it any time (for example on a hit).
  final ShaderPostFx fx;

  /// The rendered game.
  final Widget child;

  /// Snapshot resolution relative to the screen, 0.25..1.
  final double scale;

  @override
  State<ShaderPostProcessed> createState() => _ShaderPostProcessedState();
}

class _ShaderPostProcessedState extends State<ShaderPostProcessed>
    with SingleTickerProviderStateMixin {
  static const _asset = 'packages/zarvan_flutter/shaders/post_fx.frag';
  static Future<ui.FragmentProgram?>? _loading;

  final _boundary = GlobalKey();
  ui.FragmentProgram? _program;
  ui.Image? _frame;
  Ticker? _ticker;
  bool _capturing = false;
  Duration _t = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loading ??= ui.FragmentProgram.fromAsset(
      _asset,
    ).then<ui.FragmentProgram?>((p) => p).catchError((Object _) => null);
    _loading!.then((p) {
      if (mounted) setState(() => _program = p);
    });
    _ticker = createTicker((d) {
      _t = d;
      _capture();
    })..start();
  }

  Future<void> _capture() async {
    if (_capturing || _program == null || widget.fx.isIdentity) return;
    final ro = _boundary.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.attached) return;
    _capturing = true;
    try {
      final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
      final img = await ro.toImage(
        pixelRatio: dpr * widget.scale.clamp(0.25, 1.0).toDouble(),
      );
      if (!mounted) {
        img.dispose();
        return;
      }
      final old = _frame;
      setState(() => _frame = img);
      old?.dispose();
    } catch (_) {
      // A frame that cannot be captured (not painted yet) is just skipped.
    } finally {
      _capturing = false;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _frame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inner = RepaintBoundary(key: _boundary, child: widget.child);
    final frame = _frame;
    final program = _program;
    if (program == null || frame == null || widget.fx.isIdentity) return inner;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        inner,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _FxPainter(
                program,
                frame,
                widget.fx,
                _t.inMicroseconds / 1e6,
                MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FxPainter extends CustomPainter {
  _FxPainter(this.program, this.frame, this.fx, this.time, this.dpr);

  final ui.FragmentProgram program;
  final ui.Image frame;
  final ShaderPostFx fx;
  final double time;

  /// Kept for the snapshot's sharpness only: `FlutterFragCoord` is in logical
  /// pixels, so the size uniform must be logical too (device pixels shrank
  /// the picture into a corner, seen on web).
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();
    var i = 0;
    shader.setFloat(i++, size.width);
    shader.setFloat(i++, size.height);
    for (final v in fx.toUniforms(time)) {
      shader.setFloat(i++, v);
    }
    shader.setImageSampler(0, frame);
    // Not disposed here: the draw is only recorded, and freeing the shader
    // before raster read its uniforms is the suspected cause of zeroed
    // uniforms on web (unconfirmed).
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_FxPainter old) => true;
}
