import 'package:engine_flutter/engine_flutter.dart' show SpriteAtlas;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../prefs/strings.dart';
import '../textures/atlas_catalog.dart';

/// Live scrub/play preview for one AnimationClip JSON map against a project atlas.
///
/// Draws the current (or playing) frame with optional onion-skin ghosts of the
/// previous/next frames so pivots are easy to judge. Timing matches
/// `frameDurationSeconds` the same way `AnimationSystem` advances frames.
class ClipPreview extends StatefulWidget {
  final String projectRoot;
  final Map<String, dynamic> clip;
  final String? atlasId;
  final int selectedFrame;
  final bool playing;
  final bool onionSkin;

  const ClipPreview({
    super.key,
    required this.projectRoot,
    required this.clip,
    required this.atlasId,
    required this.selectedFrame,
    required this.playing,
    this.onionSkin = true,
  });

  @override
  State<ClipPreview> createState() => _ClipPreviewState();
}

class _ClipPreviewState extends State<ClipPreview>
    with SingleTickerProviderStateMixin {
  Map<String, SpriteAtlas> _atlases = const {};
  bool _loading = true;
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _elapsed = 0;
  int _playFrame = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    _load();
    if (widget.playing) {
      _playFrame = widget.selectedFrame;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(ClipPreview old) {
    super.didUpdateWidget(old);
    if (old.projectRoot != widget.projectRoot) _load();
    if (widget.playing && !old.playing) {
      _elapsed = 0;
      _last = Duration.zero;
      _playFrame = widget.selectedFrame;
      _ticker.start();
    } else if (!widget.playing && old.playing) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  Future<void> _load() async {
    _loading = true;
    final loaded = await AtlasCatalog.read(widget.projectRoot).load(
      widget.projectRoot,
    );
    if (!mounted) return;
    setState(() {
      _atlases = loaded;
      _loading = false;
    });
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero
        ? 0.0
        : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    if (dt <= 0 || dt > 0.25) return;
    final regions = (widget.clip['frameRegions'] as List?) ?? const [];
    if (regions.isEmpty) return;
    final duration =
        (widget.clip['frameDurationSeconds'] as num?)?.toDouble() ?? 0.1;
    final loop = widget.clip['loop'] as bool? ?? true;
    if (duration <= 0) return;
    _elapsed += dt;
    var changed = false;
    while (_elapsed >= duration) {
      _elapsed -= duration;
      if (_playFrame + 1 >= regions.length) {
        if (loop) {
          _playFrame = 0;
        } else {
          _playFrame = regions.length - 1;
          _ticker.stop();
        }
      } else {
        _playFrame++;
      }
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final atlasId = widget.atlasId;
    if (atlasId == null || atlasId.isEmpty) {
      return Center(
        key: const Key('clip-preview-no-atlas'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            StudioStrings.t('clip.previewPickAtlas'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final atlas = _atlases[atlasId];
    if (_loading) {
      return const Center(
        key: Key('clip-preview-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (atlas == null) {
      return Center(
        key: const Key('clip-preview-missing-atlas'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            StudioStrings.t('clip.previewMissingAtlas', {'id': atlasId}),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final regions =
        (widget.clip['frameRegions'] as List?)?.cast<String>() ?? const [];
    if (regions.isEmpty) {
      return Center(child: Text(StudioStrings.t('clip.previewEmpty')));
    }
    final frame = widget.playing
        ? _playFrame.clamp(0, regions.length - 1)
        : widget.selectedFrame.clamp(0, regions.length - 1);
    final oxList = widget.clip['frameOffsetsX'] as List?;
    final oyList = widget.clip['frameOffsetsY'] as List?;

    return ColoredBox(
      key: const Key('clip-preview'),
      color: const Color(0xFF2A2A2A),
      child: CustomPaint(
        painter: _ClipFramePainter(
          atlas: atlas,
          regions: regions,
          frame: frame,
          offsetsX: [
            for (var i = 0; i < regions.length; i++)
              (i < (oxList?.length ?? 0) ? oxList![i] as num : 0).toDouble(),
          ],
          offsetsY: [
            for (var i = 0; i < regions.length; i++)
              (i < (oyList?.length ?? 0) ? oyList![i] as num : 0).toDouble(),
          ],
          onionSkin: widget.onionSkin && !widget.playing,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ClipFramePainter extends CustomPainter {
  final SpriteAtlas atlas;
  final List<String> regions;
  final int frame;
  final List<double> offsetsX;
  final List<double> offsetsY;
  final bool onionSkin;

  _ClipFramePainter({
    required this.atlas,
    required this.regions,
    required this.frame,
    required this.offsetsX,
    required this.offsetsY,
    required this.onionSkin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.75);
    final ground = Paint()
      ..color = const Color(0x44FFFFFF)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, origin.dy), Offset(size.width, origin.dy), ground);

    void drawFrame(int i, double alpha) {
      if (i < 0 || i >= regions.length) return;
      final rect = atlas.regions[regions[i]];
      if (rect == null) return;
      final ox = i < offsetsX.length ? offsetsX[i] : 0.0;
      final oy = i < offsetsY.length ? offsetsY[i] : 0.0;
      // Center-anchored like EngineView, then apply atlas-pixel offsets.
      final dest = Rect.fromCenter(
        center: Offset(
          origin.dx + ox,
          origin.dy + oy - rect.height / 2,
        ),
        width: rect.width,
        height: rect.height,
      );
      final paint = Paint()
        ..filterQuality = FilterQuality.none
        ..color = Color.fromRGBO(255, 255, 255, alpha);
      canvas.drawImageRect(atlas.image, rect, dest, paint);
    }

    if (onionSkin) {
      drawFrame(frame - 1, 0.25);
      drawFrame(frame + 1, 0.25);
    }
    drawFrame(frame, 1.0);

    final cross = Paint()
      ..color = const Color(0xFFFF6666)
      ..strokeWidth = 1;
    canvas.drawLine(origin.translate(-8, 0), origin.translate(8, 0), cross);
    canvas.drawLine(origin.translate(0, -8), origin.translate(0, 8), cross);
  }

  @override
  bool shouldRepaint(covariant _ClipFramePainter old) =>
      old.atlas != atlas ||
      old.frame != frame ||
      old.onionSkin != onionSkin ||
      old.regions != regions ||
      old.offsetsX != offsetsX ||
      old.offsetsY != offsetsY;
}
