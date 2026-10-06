import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../level/level_geometry.dart';
import 'preview_world.dart';

/// Runs the level in the engine and draws it. Starts with [running] true and
/// rebuilds the world from the document each time it starts, so every play shows
/// the level as it is now.
class PreviewView extends StatefulWidget {
  final LevelDocument document;
  final bool running;

  /// Why the level could not be previewed, shown instead of the canvas.
  final ValueChanged<String>? onError;

  const PreviewView({
    super.key,
    required this.document,
    required this.running,
    this.onError,
  });

  @override
  State<PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<PreviewView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  PreviewWorld? _preview;
  Duration _last = Duration.zero;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.running) _start();
  }

  @override
  void didUpdateWidget(PreviewView old) {
    super.didUpdateWidget(old);
    if (widget.running && !old.running) {
      _start();
    } else if (!widget.running && old.running) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _start() {
    try {
      _preview = PreviewWorld.of(widget.document, width: 4000, height: 4000);
      _error = null;
    } on Object catch (e) {
      _error = 'The level could not be run: $e';
      widget.onError?.call(_error!);
      return;
    }
    _last = Duration.zero;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final preview = _preview;
    if (preview == null) return;
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    preview.step(dt.clamp(0.0, 1 / 30));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!, key: const Key('preview-error')));
    }
    final preview = _preview;
    if (preview == null) {
      return const Center(child: Text('Press play to run the level.'));
    }
    return CustomPaint(
      key: const Key('preview-canvas'),
      painter: _PreviewPainter(
        geometry: LevelGeometry.of(widget.document),
        positions: [
          for (final (_, pos) in preview.positions) Offset(pos.x, pos.y),
        ],
      ),
      size: Size.infinite,
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final LevelGeometry geometry;
  final List<Offset> positions;

  _PreviewPainter({required this.geometry, required this.positions});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1E1E22),
    );
    final map = geometry.tileMap;
    if (map != null) {
      final solid = Paint()..color = const Color(0xFF8A8A94);
      for (var row = 0; row < map.rows; row++) {
        for (var col = 0; col < map.cols; col++) {
          if (!map.isSolid(col, row)) continue;
          canvas.drawRect(
            Rect.fromLTWH(
              geometry.tileOrigin.dx + col * map.tileWidth,
              geometry.tileOrigin.dy + row * map.tileHeight,
              map.tileWidth,
              map.tileHeight,
            ),
            solid,
          );
        }
      }
    }
    final marker = Paint()..color = const Color(0xFFE0474C);
    for (final at in positions) {
      canvas.drawCircle(at, 5, marker);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
