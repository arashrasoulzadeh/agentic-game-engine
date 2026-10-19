import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart' show Tween;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Tween;

import 'scene_transition.dart';

/// Paints a frozen snapshot of the *outgoing* scene over the live *incoming* one,
/// progressively revealing it -- the slide, crossfade and pixel-dissolve
/// transitions.
///
/// Drawing a snapshot rather than rendering two `World`s at once is deliberate:
/// the outgoing `World` is gone the moment the new scene loads (a `Scene` owns its
/// `World`), and a still frame is all these effects ever show of it. It costs one
/// GPU image and needs no changes to `World` or `EngineView`.
class SnapshotTransitionPainter extends CustomPainter {
  SnapshotTransitionPainter({
    required this.snapshot,
    required this.type,
    required this.progress,
    this.pixelSize = 16,
    this.seed = 1,
  });

  final ui.Image snapshot;
  final SceneTransitionType type;

  /// 0 = the snapshot fully covers the screen, 1 = fully gone.
  final double progress;

  /// Edge of a dissolve block, in logical pixels.
  final double pixelSize;

  /// Varies the dissolve pattern; the same seed always gives the same pattern.
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      snapshot.width.toDouble(),
      snapshot.height.toDouble(),
    );
    final dst = Offset.zero & size;
    final t = progress.clamp(0.0, 1.0);
    switch (type) {
      case SceneTransitionType.slideLeft:
        canvas.drawImageRect(
          snapshot,
          src,
          dst.shift(Offset(-size.width * t, 0)),
          Paint(),
        );
      case SceneTransitionType.slideRight:
        canvas.drawImageRect(
          snapshot,
          src,
          dst.shift(Offset(size.width * t, 0)),
          Paint(),
        );
      case SceneTransitionType.slideUp:
        canvas.drawImageRect(
          snapshot,
          src,
          dst.shift(Offset(0, -size.height * t)),
          Paint(),
        );
      case SceneTransitionType.slideDown:
        canvas.drawImageRect(
          snapshot,
          src,
          dst.shift(Offset(0, size.height * t)),
          Paint(),
        );
      case SceneTransitionType.crossfade:
        canvas.drawImageRect(
          snapshot,
          src,
          dst,
          Paint()
            ..color = Color.fromARGB(((1 - t) * 255).round(), 255, 255, 255),
        );
      case SceneTransitionType.pixelDissolve:
        _paintDissolve(canvas, size, src, t);
      case SceneTransitionType.fade:
      case SceneTransitionType.iris:
        // World-based transitions (screen tint / clip shape); they never paint a
        // snapshot, so there is nothing to draw if one is asked for.
        break;
    }
  }

  void _paintDissolve(Canvas canvas, Size size, Rect src, double t) {
    final cols = (size.width / pixelSize).ceil();
    final rows = (size.height / pixelSize).ceil();
    final sx = src.width / size.width;
    final sy = src.height / size.height;
    final paint = Paint();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (dissolveThreshold(c, r, seed) < t) continue;
        final dst = Rect.fromLTWH(
          c * pixelSize,
          r * pixelSize,
          pixelSize,
          pixelSize,
        ).intersect(Offset.zero & size);
        canvas.drawImageRect(
          snapshot,
          Rect.fromLTRB(
            dst.left * sx,
            dst.top * sy,
            dst.right * sx,
            dst.bottom * sy,
          ),
          dst,
          paint,
        );
      }
    }
  }

  /// A stable pseudo-random value in [0, 1) for a block. A block disappears once
  /// `progress` passes it, so across a full run every block goes exactly once and
  /// the same blocks go first every time for a given [seed] (replayable).
  static double dissolveThreshold(int col, int row, int seed) {
    var h = (col * 73856093) ^ (row * 19349663) ^ (seed * 83492791);
    h = (h ^ (h >> 13)) * 1274126177;
    h = h ^ (h >> 16);
    return (h & 0xFFFF) / 0x10000;
  }

  @override
  bool shouldRepaint(SnapshotTransitionPainter old) =>
      old.progress != progress || old.snapshot != snapshot || old.type != type;
}

/// Plays the snapshot transition described by [config] over [snapshot], calling
/// [onDone] when it finishes. Ignores pointer events so the incoming scene is
/// playable underneath.
class SnapshotTransition extends StatefulWidget {
  const SnapshotTransition({
    super.key,
    required this.snapshot,
    required this.config,
    required this.onDone,
  });

  final ui.Image snapshot;
  final SceneTransitionConfig config;
  final VoidCallback onDone;

  @override
  State<SnapshotTransition> createState() => _SnapshotTransitionState();
}

class _SnapshotTransitionState extends State<SnapshotTransition>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final Tween _tween;
  Duration _last = Duration.zero;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _tween = Tween(
      from: 0.0,
      to: 1.0,
      duration: widget.config.duration,
      easing: widget.config.easing,
    );
    _ticker = createTicker((elapsed) {
      _tween.elapsed += (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      setState(() => _progress = _tween.value);
      if (_tween.isComplete) {
        _ticker.stop();
        widget.onDone();
      }
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const Key('snapshot-transition'),
          size: Size.infinite,
          painter: SnapshotTransitionPainter(
            snapshot: widget.snapshot,
            type: widget.config.type,
            progress: _progress,
            seed: math.max(1, widget.config.duration.hashCode),
          ),
        ),
      ),
    );
  }
}
