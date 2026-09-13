import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import 'camera.dart';
import 'components/parallax_layer.dart';
import 'components/sprite.dart';
// Aliased -- `Text` collides with Flutter's own widget of the same
// name, which `package:flutter/widgets.dart` (imported above) already
// brings into scope.
import 'components/text.dart' as txt;
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

  /// Called with the tap/click position converted to world coordinates
  /// via `camera.screenToWorld` — how a `Scene.handleTap` implementation
  /// (an ECS menu button, a door tapped in-world) learns where the
  /// player tapped without touching screen coordinates itself. Null (the
  /// default) disables tap handling entirely, so a game with no
  /// tap-driven UI pays nothing for it.
  final void Function(Offset worldPosition)? onWorldTap;

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
    this.onWorldTap,
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
    // Decays/recomputes any active Camera.shake() offset -- called
    // unconditionally (not just when cameraFollowEntity is set), since
    // a static camera still needs to shake on e.g. an explosion.
    widget.camera.update(dt);

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

    if (controller != null) {
      child = Focus(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (node, event) => controller.handleKeyEvent(event),
        child: child,
      );
    }

    final onWorldTap = widget.onWorldTap;
    if (onWorldTap == null) return child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapUp: (details) {
        final box = context.findRenderObject() as RenderBox?;
        onWorldTap(widget.camera.screenToWorld(details.localPosition, box?.size ?? Size.zero));
      },
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
    final items = <_DrawItem>[];
    var order = 0;
    order = _collectParallaxItems(items, order, size, positions);
    order = _collectTileMapItems(items, order, size, positions);
    order = _collectSpriteItems(items, order, size, positions);
    order = _collectParticleItems(items, order, size, positions);
    _collectTextItems(items, order, size, positions);

    // Stable by construction (`order` is a strictly increasing
    // tie-breaker assigned in the engine's original draw order --
    // parallax, then tiles, then sprites, then particles, each in
    // ComponentStore order) -- ties at the same zIndex (the default:
    // everything at 0) reproduce that original order exactly.
    items.sort((a, b) {
      final byZ = a.zIndex.compareTo(b.zIndex);
      return byZ != 0 ? byZ : a.order.compareTo(b.order);
    });

    for (final item in items) {
      item.paint(canvas);
    }
  }

  @override
  bool shouldRepaint(covariant _EnginePainter oldDelegate) => true;

  /// Collects one `_DrawItem` per shared-atlas batch (plus one per
  /// non-batchable fallback sprite), grouped by `Sprite.zIndex` first so
  /// items land in the right slot once `paint()` sorts everything —
  /// batching only ever combines sprites that already share both a
  /// `zIndex` and an atlas, so it can't smear a sprite across the wrong
  /// z-slot.
  ///
  /// Batching itself: `Canvas.drawAtlas` draws many sprites from one
  /// source image in a single call with no per-sprite canvas state
  /// changes — meaningfully cheaper than a `save`/`translate`/`scale`/
  /// `drawImageRect`/`restore` sequence per sprite at sprite-heavy
  /// scenes. `RSTransform` (what `drawAtlas` takes per sprite) only
  /// supports one *positive, uniform* scale factor, not independent X/Y
  /// scale — so a sprite with `scaleX != scaleY`, or a negative one (the
  /// standard way `FacingSystem` flips a sprite horizontally), can't be
  /// expressed that way and falls back to the original per-sprite
  /// `drawImageRect` path instead.
  int _collectSpriteItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final sprites = world.storeOf<Sprite>();
    if (sprites.length == 0) return order;

    final indicesByZ = <int, List<int>>{};
    for (var i = 0; i < sprites.length; i++) {
      final entity = sprites.entityAt(i);
      final sprite = sprites.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null || !atlasRegistry.has(sprite.atlasId)) continue;
      (indicesByZ[sprite.zIndex] ??= []).add(i);
    }

    for (final zEntry in indicesByZ.entries) {
      final z = zEntry.key;
      final batchesByImage = <ui.Image, _SpriteBatch>{};
      final fallbackIndices = <int>[];

      for (final i in zEntry.value) {
        final entity = sprites.entityAt(i);
        final sprite = sprites.denseAt(i);
        if (sprite.scaleX != sprite.scaleY || sprite.scaleX <= 0) {
          fallbackIndices.add(i);
          continue;
        }

        final pos = positions.get(entity)!;
        final atlas = atlasRegistry.resolve(sprite.atlasId);
        final srcRect = atlas.regionFor(sprite.region);
        final screenPos = camera.worldToScreen(pos.x, pos.y, size);

        final batch = batchesByImage.putIfAbsent(atlas.image, () => _SpriteBatch());
        batch.transforms.add(RSTransform.fromComponents(
          rotation: sprite.rotation,
          scale: sprite.scaleX * camera.zoom,
          anchorX: srcRect.width / 2,
          anchorY: srcRect.height / 2,
          translateX: screenPos.dx,
          translateY: screenPos.dy,
        ));
        batch.rects.add(srcRect);
      }

      if (batchesByImage.isNotEmpty) {
        items.add(_DrawItem(z, order++, (canvas) {
          final paint = Paint();
          for (final entry in batchesByImage.entries) {
            canvas.drawAtlas(entry.key, entry.value.transforms, entry.value.rects, null, null, null, paint);
          }
        }));
      }
      for (final i in fallbackIndices) {
        items.add(_DrawItem(
          z,
          order++,
          (canvas) => _paintSpriteIndividually(canvas, size, positions, sprites, i),
        ));
      }
    }
    return order;
  }

  void _paintSpriteIndividually(
    Canvas canvas,
    Size size,
    ComponentStore<Position> positions,
    ComponentStore<Sprite> sprites,
    int i,
  ) {
    final entity = sprites.entityAt(i);
    final sprite = sprites.denseAt(i);
    final pos = positions.get(entity)!;
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
    canvas.drawImageRect(atlas.image, srcRect, destRect, Paint());
    canvas.restore();
  }

  /// Collects one `_DrawItem` per `Particle` (from `ParticleSystem`),
  /// grouped by `Particle.zIndex` — defaults land after sprites, the
  /// common case for hit sparks/dust/collect flair sitting above
  /// gameplay art rather than under it. A particle with its own
  /// `Sprite` component (the game attached one for a textured look)
  /// draws that region scaled by `Particle.scale`; otherwise a plain
  /// circle of `Particle.colorArgb`. Both fade via `Particle.alpha` —
  /// for the sprite case that relies on the paint's alpha channel
  /// modulating the whole `drawImageRect` call, the standard Flutter
  /// trick for compositing an image at partial opacity without a
  /// `saveLayer` per particle.
  int _collectParticleItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final particles = world.storeOf<Particle>();
    if (particles.length == 0) return order;

    final sprites = world.storeOf<Sprite>();
    for (var i = 0; i < particles.length; i++) {
      final entity = particles.entityAt(i);
      final particle = particles.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;

      final alpha = particle.alpha.clamp(0.0, 1.0);
      if (alpha <= 0 || particle.scale <= 0) continue;

      items.add(_DrawItem(particle.zIndex, order++, (canvas) {
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
      }));
    }
    return order;
  }

  /// Collects one `_DrawItem` per `ParallaxLayer`, defaulting to before
  /// tiles/sprites/particles (see `Sprite.zIndex`). Each layer's screen
  /// anchor scales the camera by `scrollFactorX`/`Y` instead of using it
  /// 1:1 like `worldToScreen` does for regular sprites — that scaled-
  /// down camera movement is the entire parallax effect. `tileX`/`tileY`
  /// repeat the region across the viewport by drawing it at every
  /// `_tileStarts` offset instead of once, so one authored strip covers
  /// arbitrarily wide/tall scrolling.
  int _collectParallaxItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final layers = world.storeOf<ParallaxLayer>();
    if (layers.length == 0) return order;

    for (var i = 0; i < layers.length; i++) {
      final entity = layers.entityAt(i);
      final layer = layers.denseAt(i);
      if (!atlasRegistry.has(layer.atlasId)) continue;

      items.add(_DrawItem(layer.zIndex, order++, (canvas) {
        final atlas = atlasRegistry.resolve(layer.atlasId);
        final srcRect = atlas.regionFor(layer.region);
        final tileWidth = srcRect.width * camera.zoom;
        final tileHeight = srcRect.height * camera.zoom;
        if (tileWidth <= 0 || tileHeight <= 0) return;

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
      }));
    }
    return order;
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

  /// Collects one `_DrawItem` per `TileMap`, grouped by `TileMap.zIndex`
  /// (defaults to before sprites/particles, same as before this became
  /// z-sortable) — draws every non-empty tile as a solid-colored rect
  /// (no atlas lookup, since tiles are level geometry, not sprites; a
  /// game wanting textured tiles draws them as regular `Sprite`
  /// entities instead, or a foreground `TileMap` with a higher `zIndex`
  /// for a mask/overhang layer).
  int _collectTileMapItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final tileMaps = world.storeOf<TileMap>();
    for (var m = 0; m < tileMaps.length; m++) {
      final mapEntity = tileMaps.entityAt(m);
      final map = tileMaps.denseAt(m);

      items.add(_DrawItem(map.zIndex, order++, (canvas) {
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
      }));
    }
    return order;
  }

  /// Collects one `_DrawItem` per `Text` — drawn fresh every frame via
  /// `TextPainter`, not batched (unlike sprites), since text doesn't
  /// share a source image the way atlas-based sprites do. `screenSpace`
  /// text skips the camera transform entirely (`Position` is already in
  /// viewport pixels); world-space text goes through `camera.worldToScreen`
  /// like a `Sprite`, so it scrolls/zooms with everything else.
  int _collectTextItems(
    List<_DrawItem> items,
    int order,
    Size size,
    ComponentStore<Position> positions,
  ) {
    final texts = world.storeOf<txt.Text>();
    for (var i = 0; i < texts.length; i++) {
      final entity = texts.entityAt(i);
      final text = texts.denseAt(i);
      final pos = positions.get(entity);
      if (pos == null) continue;

      items.add(_DrawItem(text.zIndex, order++, (canvas) {
        final screenPos =
            text.screenSpace ? Offset(pos.x, pos.y) : camera.worldToScreen(pos.x, pos.y, size);
        final painter = TextPainter(
          text: TextSpan(
            text: text.text,
            style: TextStyle(
              color: Color(text.colorArgb),
              fontSize: text.fontSize * (text.screenSpace ? 1 : camera.zoom),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        final dx = switch (text.align) {
          txt.TextAlignment.left => 0.0,
          txt.TextAlignment.center => -painter.width / 2,
          txt.TextAlignment.right => -painter.width,
        };
        painter.paint(canvas, Offset(screenPos.dx + dx, screenPos.dy - painter.height / 2));
      }));
    }
    return order;
  }
}

/// One item in the z-sorted draw list `_EnginePainter.paint` builds —
/// see its doc comment and `Sprite.zIndex` for the full ordering rule.
/// [order] is a tie-breaker for items sharing the same [zIndex],
/// assigned in the engine's original fixed draw order (parallax, tiles,
/// sprites, particles) so the common case (everything at the default
/// zIndex 0) renders identically to before z-index existed.
class _DrawItem {
  final int zIndex;
  final int order;
  final void Function(Canvas canvas) paint;
  _DrawItem(this.zIndex, this.order, this.paint);
}

/// One `Canvas.drawAtlas` call's worth of sprites sharing a source
/// image — see `_EnginePainter._collectSpriteItems`.
class _SpriteBatch {
  final transforms = <RSTransform>[];
  final rects = <Rect>[];
}
