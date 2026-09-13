import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import 'camera.dart';
import 'components/parallax_layer.dart';
import 'components/sprite.dart';
import 'debug_memory.dart';
import 'input.dart';
import 'sprite_atlas.dart';

/// The Flutter shell: owns the game loop (Ticker -> `world.step(dt)`),
/// forwards keyboard input, and paints sprites. Contains zero gameplay
/// logic — everything it reads comes from `World` component stores, so a
/// game built on this never has to hand-roll ticker/painter boilerplate
/// (previously duplicated in the CLI template and the stress-test app).
class EngineView extends StatefulWidget {
  final World world;
  final AtlasRegistry atlasRegistry;
  final Camera camera;
  final InputController? inputController;
  final EntityId? cameraFollowEntity;
  final Color backgroundColor;
  final bool paused;

  /// Shows a top-left debug panel: fps, tick count, live entity/sprite/
  /// particle counts, and resident memory (where available — not on
  /// web, `dart:io` has no memory API there, so that line is omitted).
  final bool showFpsOverlay;

  const EngineView({
    super.key,
    required this.world,
    required this.atlasRegistry,
    required this.camera,
    this.inputController,
    this.cameraFollowEntity,
    this.backgroundColor = const Color(0xFF000000),
    this.paused = false,
    this.showFpsOverlay = false,
  });

  @override
  State<EngineView> createState() => _EngineViewState();
}

class _EngineViewState extends State<EngineView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  final FocusNode _focusNode = FocusNode();
  double _fps = 0;
  int? _memoryBytes;
  int _memorySampleCounter = 0;
  final List<double> _recentDts = [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.25) return;
    if (widget.paused) return;

    widget.world.step(dt);

    if (widget.showFpsOverlay) {
      _recentDts.add(dt);
      if (_recentDts.length > 30) _recentDts.removeAt(0);
      final avgDt = _recentDts.reduce((a, b) => a + b) / _recentDts.length;
      _fps = avgDt > 0 ? 1 / avgDt : 0;

      // Sampling every ~30 ticks (not every frame) since reading RSS
      // is comparatively expensive and this is a debug readout, not
      // something the render loop should pay full cost for.
      _memorySampleCounter++;
      if (_memorySampleCounter >= 30) {
        _memorySampleCounter = 0;
        _memoryBytes = currentMemoryUsageBytes();
      }
    }

    final followId = widget.cameraFollowEntity;
    if (followId != null) {
      final pos = widget.world.storeOf<Position>().get(followId);
      if (pos != null) {
        final box = context.findRenderObject() as RenderBox?;
        widget.camera.follow(
          pos.x,
          pos.y,
          viewportSize: box?.size,
          worldWidth: widget.world.width,
          worldHeight: widget.world.height,
        );
      }
    }

    setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// fps/tick/entity-sprite-particle counts, plus memory where
  /// available (not on web — see `debug_memory.dart`). Reads
  /// `storeOf<TileMap>`/`storeOf<Particle>` the same as the painter
  /// does, so it assumes the same `registerCoreComponents`/
  /// `registerFlutterComponents` precondition `EngineView` already has.
  String _debugText() {
    final world = widget.world;
    return [
      'fps: ${_fps.toStringAsFixed(0)}',
      'tick: ${world.tick}',
      'entities: ${world.entities.count}',
      'sprites: ${world.storeOf<Sprite>().length}',
      'particles: ${world.storeOf<Particle>().length}',
      if (_memoryBytes case final mem?) 'mem: ${(mem / (1024 * 1024)).toStringAsFixed(1)} MB',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.inputController;
    final painter = _EnginePainter(
      world: widget.world,
      atlasRegistry: widget.atlasRegistry,
      camera: widget.camera,
      backgroundColor: widget.backgroundColor,
    );

    Widget child = CustomPaint(painter: painter, size: Size.infinite);

    if (widget.showFpsOverlay) {
      child = Stack(
        children: [
          child,
          Positioned(
            left: 4,
            top: 4,
            child: Text(
              _debugText(),
              style: const TextStyle(
                color: Color(0xFF00FF00),
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      );
    }

    if (controller == null) return child;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) => controller.handleKeyEvent(event),
      child: child,
    );
  }
}

class _EnginePainter extends CustomPainter {
  final World world;
  final AtlasRegistry atlasRegistry;
  final Camera camera;
  final Color backgroundColor;

  _EnginePainter({
    required this.world,
    required this.atlasRegistry,
    required this.camera,
    required this.backgroundColor,
  }) : super(repaint: null);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = backgroundColor);

    final positions = world.storeOf<Position>();
    _paintParallaxLayers(canvas, size, positions);
    _paintTileMaps(canvas, size, positions);

    final sprites = world.storeOf<Sprite>();
    final paint = Paint();

    for (var i = 0; i < sprites.length; i++) {
      final entity = sprites.entityAt(i);
      final sprite = sprites.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null || !atlasRegistry.has(sprite.atlasId)) continue;

      final atlas = atlasRegistry.resolve(sprite.atlasId);
      final srcRect = atlas.regionFor(sprite.region);
      final screenPos = camera.worldToScreen(pos.x, pos.y, size);

      canvas.save();
      canvas.translate(screenPos.dx, screenPos.dy);
      if (sprite.rotation != 0) canvas.rotate(sprite.rotation);
      canvas.scale(
        sprite.scaleX * camera.zoom,
        sprite.scaleY * camera.zoom,
      );
      final destRect = ui.Rect.fromCenter(
        center: Offset.zero,
        width: srcRect.width,
        height: srcRect.height,
      );
      canvas.drawImageRect(atlas.image, srcRect, destRect, paint);
      canvas.restore();
    }

    _paintParticles(canvas, size, positions);
  }

  @override
  bool shouldRepaint(covariant _EnginePainter oldDelegate) => true;

  /// Draws every `Particle` (from `ParticleSystem`) on top of sprites —
  /// the common case for hit sparks/dust/collect flair sitting above
  /// gameplay art rather than under it. A particle with its own
  /// `Sprite` component (the game attached one for a textured look)
  /// draws that region scaled by `Particle.scale`; otherwise a plain
  /// circle of `Particle.colorArgb`. Both fade via `Particle.alpha` —
  /// for the sprite case that relies on the paint's alpha channel
  /// modulating the whole `drawImageRect` call, the standard Flutter
  /// trick for compositing an image at partial opacity without a
  /// `saveLayer` per particle.
  void _paintParticles(Canvas canvas, Size size, ComponentStore<Position> positions) {
    final particles = world.storeOf<Particle>();
    if (particles.length == 0) return;

    final sprites = world.storeOf<Sprite>();
    for (var i = 0; i < particles.length; i++) {
      final entity = particles.entityAt(i);
      final particle = particles.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;

      final alpha = particle.alpha.clamp(0.0, 1.0);
      if (alpha <= 0 || particle.scale <= 0) continue;

      final screenPos = camera.worldToScreen(pos.x, pos.y, size);
      final sprite = sprites.get(entity);
      if (sprite != null && atlasRegistry.has(sprite.atlasId)) {
        final atlas = atlasRegistry.resolve(sprite.atlasId);
        final srcRect = atlas.regionFor(sprite.region);
        final destRect = ui.Rect.fromCenter(
          center: screenPos,
          width: srcRect.width * particle.scale * camera.zoom,
          height: srcRect.height * particle.scale * camera.zoom,
        );
        canvas.drawImageRect(
          atlas.image,
          srcRect,
          destRect,
          Paint()..color = Color.fromRGBO(255, 255, 255, alpha),
        );
      } else {
        final base = Color(particle.colorArgb);
        canvas.drawCircle(
          screenPos,
          4 * particle.scale * camera.zoom,
          Paint()..color = base.withValues(alpha: alpha * base.a),
        );
      }
    }
  }

  /// Draws every `ParallaxLayer`, first (behind tiles/sprites/particles).
  /// Each layer's screen anchor scales the camera by `scrollFactorX`/`Y`
  /// instead of using it 1:1 like `worldToScreen` does for regular
  /// sprites — that scaled-down camera movement is the entire parallax
  /// effect. `tileX`/`tileY` repeat the region across the viewport by
  /// drawing it at every `_tileStarts` offset instead of once, so one
  /// authored strip covers arbitrarily wide/tall scrolling.
  void _paintParallaxLayers(Canvas canvas, Size size, ComponentStore<Position> positions) {
    final layers = world.storeOf<ParallaxLayer>();
    if (layers.length == 0) return;

    for (var i = 0; i < layers.length; i++) {
      final entity = layers.entityAt(i);
      final layer = layers.denseAt(i);
      if (!atlasRegistry.has(layer.atlasId)) continue;

      final atlas = atlasRegistry.resolve(layer.atlasId);
      final srcRect = atlas.regionFor(layer.region);
      final tileWidth = srcRect.width * camera.zoom;
      final tileHeight = srcRect.height * camera.zoom;
      if (tileWidth <= 0 || tileHeight <= 0) continue;

      final pos = positions.get(entity) ?? Position(0, 0);
      final anchorX =
          (pos.x - camera.x * layer.scrollFactorX) * camera.zoom + size.width / 2;
      final anchorY =
          (pos.y - camera.y * layer.scrollFactorY) * camera.zoom + size.height / 2;

      final xs = layer.tileX ? _tileStarts(anchorX, tileWidth, size.width) : [anchorX];
      final ys = layer.tileY ? _tileStarts(anchorY, tileHeight, size.height) : [anchorY];

      final paint = Paint();
      for (final y in ys) {
        for (final x in xs) {
          canvas.drawImageRect(
            atlas.image,
            srcRect,
            Rect.fromLTWH(x, y, tileWidth, tileHeight),
            paint,
          );
        }
      }
    }
  }

  /// Every `tileSize`-spaced offset from at-or-before 0 up to
  /// [viewportSize], starting from [anchor] — i.e. the set of positions
  /// to draw one tile at so the whole viewport is covered with no gaps,
  /// regardless of how far [anchor] has scrolled. Dart's `%` is floored
  /// (always non-negative for a positive divisor), so this works the
  /// same for a negative [anchor] as a positive one.
  List<double> _tileStarts(double anchor, double tileSize, double viewportSize) {
    var start = anchor % tileSize;
    if (start > 0) start -= tileSize;
    return [for (var x = start; x < viewportSize; x += tileSize) x];
  }

  /// Draws every non-empty tile of every `TileMap` in the world — this
  /// was missing entirely until now: `TileMap` only ever fed collision
  /// (`PlatformerSystem`/`TileCollisionSystem`), so a game using tiles
  /// for its level geometry had physically correct but *invisible*
  /// ground/platforms. Solid-colored rects only (no atlas lookup) since
  /// tiles are level geometry, not sprites — a game wanting textured
  /// tiles draws them as regular `Sprite` entities instead.
  void _paintTileMaps(Canvas canvas, Size size, ComponentStore<Position> positions) {
    final tileMaps = world.storeOf<TileMap>();
    for (var m = 0; m < tileMaps.length; m++) {
      final mapEntity = tileMaps.entityAt(m);
      final map = tileMaps.denseAt(m);
      final origin = positions.get(mapEntity) ?? Position(0, 0);

      for (var row = 0; row < map.rows; row++) {
        for (var col = 0; col < map.cols; col++) {
          final tileId = map.tileAt(col, row);
          if (tileId == 0) continue;

          final left = origin.x + col * map.tileWidth;
          final top = origin.y + row * map.tileHeight;
          final screenPos = camera.worldToScreen(left, top, size);
          final color = map.oneWayTileIds.contains(tileId)
              ? const Color(0x8899CCFF)
              : const Color(0xFF4A4A4A);

          canvas.drawRect(
            Rect.fromLTWH(
              screenPos.dx,
              screenPos.dy,
              map.tileWidth * camera.zoom,
              map.tileHeight * camera.zoom,
            ),
            Paint()..color = color,
          );
        }
      }
    }
  }
}
