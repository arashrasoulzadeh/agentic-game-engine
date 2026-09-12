import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart';

import 'camera.dart';
import 'components/sprite.dart';
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
              'fps: ${_fps.toStringAsFixed(0)}',
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
  }

  @override
  bool shouldRepaint(covariant _EnginePainter oldDelegate) => true;

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
