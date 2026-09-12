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

  const EngineView({
    super.key,
    required this.world,
    required this.atlasRegistry,
    required this.camera,
    this.inputController,
    this.cameraFollowEntity,
    this.backgroundColor = const Color(0xFF000000),
  });

  @override
  State<EngineView> createState() => _EngineViewState();
}

class _EngineViewState extends State<EngineView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  final FocusNode _focusNode = FocusNode();

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

    widget.world.step(dt);

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

    final child = CustomPaint(painter: painter, size: Size.infinite);

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
}
