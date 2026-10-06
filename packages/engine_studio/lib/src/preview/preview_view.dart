import 'package:engine_core/engine_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:engine_flutter/engine_flutter.dart' show Sprite, SpriteAtlas;
import 'package:flutter/services.dart';

import '../level/level_geometry.dart';
import '../textures/atlas_catalog.dart';
import 'preview_world.dart';

/// The game actions the preview's controls send, keyed by the names the platformer
/// input system listens for.
final _leftKeys = {LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA};
final _rightKeys = {LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD};
final _jumpKeys = {
  LogicalKeyboardKey.space,
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.keyW,
};

/// Runs the level in the engine and draws it. Starts with [running] true and
/// rebuilds the world from the document each time it starts, so every play shows
/// the level as it is now.
///
/// Controls: arrow keys or A/D to move, Space or W to jump, and on-screen Left,
/// Jump, and Right buttons for the same actions. Fit width scales the whole level
/// to the window's width, so a wide level can be seen at once.
class PreviewView extends StatefulWidget {
  final LevelDocument document;
  final bool running;

  /// The project whose atlas catalog supplies the art. Null draws plain shapes only.
  final String? projectRoot;

  const PreviewView({
    super.key,
    required this.document,
    required this.running,
    this.projectRoot,
  });

  @override
  State<PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<PreviewView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  final FocusNode _focus = FocusNode();
  final Set<String> _held = {};
  PreviewWorld? _preview;
  Duration _last = Duration.zero;
  String? _error;
  bool _fitWidth = true;
  bool _textures = true;
  Map<String, SpriteAtlas> _atlases = const {};

  @override
  void initState() {
    super.initState();
    if (widget.running) {
      _start();
    }
    _loadAtlases();
  }

  Future<void> _loadAtlases() async {
    final root = widget.projectRoot;
    if (root == null) return;
    final loaded = await AtlasCatalog.read(root).load(root);
    if (mounted) setState(() => _atlases = loaded);
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
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    try {
      _preview = PreviewWorld.of(widget.document, width: 4000, height: 4000);
      _error = null;
    } on Object catch (e) {
      _error = 'The level could not be run: $e';
      return;
    }
    _held.clear();
    _last = Duration.zero;
    _ticker.start();
    _focus.requestFocus();
  }

  void _onTick(Duration elapsed) {
    final preview = _preview;
    if (preview == null) {
      return;
    }
    final dt =
        (elapsed - _last).inMicroseconds / Duration.microsecondsPerSecond;
    _last = elapsed;
    preview.step(dt.clamp(0.0, 1 / 30).toDouble());
    setState(() {});
  }

  /// The game action a key stands for, or null when it is not a control.
  String? _actionFor(LogicalKeyboardKey key) {
    if (_leftKeys.contains(key)) return 'left';
    if (_rightKeys.contains(key)) return 'right';
    if (_jumpKeys.contains(key)) return 'jump';
    return null;
  }

  void _hold(String action, bool down) {
    setState(() {
      if (down) {
        _held.add(action);
      } else {
        _held.remove(action);
      }
    });
    _preview?.pressActions(Set.of(_held));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final action = _actionFor(event.logicalKey);
    if (action == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) _hold(action, true);
    if (event is KeyUpEvent) _hold(action, false);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Center(child: Text(error, key: const Key('preview-error')));
    }
    final preview = _preview;
    if (preview == null) {
      return const Center(child: Text('Press play to run the level.'));
    }

    final geometry = LevelGeometry.of(widget.document);
    final drawables = [
      for (final (pos, sprite) in preview.drawables)
        _Drawable(Offset(pos.x, pos.y), sprite),
    ];
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(
        children: [
          _Controls(
            fitWidth: _fitWidth,
            onFitChanged: (value) => setState(() => _fitWidth = value),
            textures: _textures,
            hasTextures: _atlases.isNotEmpty,
            onTexturesChanged: (value) => setState(() => _textures = value),
            onHold: _hold,
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final levelWidth = _levelWidth(geometry);
                final scale = _fitWidth && levelWidth > 0
                    ? constraints.maxWidth / levelWidth
                    : 1.0;
                return ClipRect(
                  child: CustomPaint(
                    key: const Key('preview-canvas'),
                    size: Size.infinite,
                    painter: _PreviewPainter(
                      geometry: geometry,
                      drawables: drawables,
                      scale: scale,
                      atlases: _textures ? _atlases : const {},
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Width of the level in world units, from its tile map, or 0 when there is none.
  double _levelWidth(LevelGeometry geometry) {
    final map = geometry.tileMap;
    if (map == null) return 0;
    return map.cols * map.tileWidth;
  }
}

/// The toolbar above the preview: the on-screen movement buttons and the Fit width
/// toggle.
class _Controls extends StatelessWidget {
  final bool fitWidth;
  final ValueChanged<bool> onFitChanged;
  final bool textures;
  final bool hasTextures;
  final ValueChanged<bool> onTexturesChanged;
  final void Function(String action, bool down) onHold;

  const _Controls({
    required this.fitWidth,
    required this.onFitChanged,
    required this.textures,
    required this.hasTextures,
    required this.onTexturesChanged,
    required this.onHold,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _HoldButton(
              key: const Key('control-left'),
              label: 'Left',
              action: 'left',
              onHold: onHold,
            ),
            const SizedBox(width: 8),
            _HoldButton(
              key: const Key('control-jump'),
              label: 'Jump',
              action: 'jump',
              onHold: onHold,
            ),
            const SizedBox(width: 8),
            _HoldButton(
              key: const Key('control-right'),
              label: 'Right',
              action: 'right',
              onHold: onHold,
            ),
            const SizedBox(width: 16),
            const Text('Fit width'),
            Switch(
              key: const Key('fit-width'),
              value: fitWidth,
              onChanged: onFitChanged,
            ),
            const SizedBox(width: 8),
            Text(hasTextures ? 'Textures' : 'Textures (none declared)'),
            Switch(
              key: const Key('textures'),
              value: textures && hasTextures,
              onChanged: hasTextures ? onTexturesChanged : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A button that counts as held while it is pressed, like the key it stands for.
class _HoldButton extends StatelessWidget {
  final String label;
  final String action;
  final void Function(String action, bool down) onHold;

  const _HoldButton({
    super.key,
    required this.label,
    required this.action,
    required this.onHold,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => onHold(action, true),
      onPointerUp: (_) => onHold(action, false),
      onPointerCancel: (_) => onHold(action, false),
      child: FilledButton.tonal(onPressed: () {}, child: Text(label)),
    );
  }
}

/// One entity to draw: where it is, and its sprite if it has one.
class _Drawable {
  final Offset at;
  final Sprite? sprite;

  const _Drawable(this.at, this.sprite);
}

class _PreviewPainter extends CustomPainter {
  final LevelGeometry geometry;
  final List<_Drawable> drawables;
  final double scale;
  final Map<String, SpriteAtlas> atlases;

  _PreviewPainter({
    required this.geometry,
    required this.drawables,
    required this.scale,
    required this.atlases,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF1E1E22),
    );
    canvas.save();
    canvas.scale(scale);
    final map = geometry.tileMap;
    if (map != null) {
      final solid = Paint()..color = const Color(0xFF8A8A94);
      for (var row = 0; row < map.rows; row++) {
        for (var col = 0; col < map.cols; col++) {
          if (!map.isSolid(col, row)) continue;
          final dst = Rect.fromLTWH(
            geometry.tileOrigin.dx + col * map.tileWidth,
            geometry.tileOrigin.dy + row * map.tileHeight,
            map.tileWidth,
            map.tileHeight,
          );
          if (_drawTexture(canvas, map, map.tileAt(col, row), dst)) continue;
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
    for (final drawable in drawables) {
      if (_drawSprite(canvas, drawable)) {
        continue;
      }
      canvas.drawCircle(drawable.at, 5, marker);
    }
    canvas.restore();
  }

  /// Draws the tile's region from its atlas. Returns false when there is no atlas
  /// or region for it, so the caller falls back to the plain shape.
  bool _drawTexture(Canvas canvas, TileMap map, int tileId, Rect dst) {
    final atlasId = map.atlasId;
    final regionName = map.regionByTileId[tileId];
    if (atlasId == null || regionName == null) return false;
    final atlas = atlases[atlasId];
    if (atlas == null || !atlas.regions.containsKey(regionName)) return false;
    canvas.drawImageRect(
      atlas.image,
      atlas.regionFor(regionName),
      dst,
      Paint(),
    );
    return true;
  }

  /// Draws an entity's sprite region, centred on its position and scaled as the
  /// sprite says. Returns false when the entity has no sprite or its atlas is not
  /// loaded, so the caller draws a marker.
  bool _drawSprite(Canvas canvas, _Drawable drawable) {
    final sprite = drawable.sprite;
    if (sprite == null) return false;
    final atlas = atlases[sprite.atlasId];
    if (atlas == null || !atlas.regions.containsKey(sprite.region)) {
      return false;
    }
    final src = atlas.regionFor(sprite.region);
    final w = src.width * sprite.scaleX;
    final h = src.height * sprite.scaleY;
    final dst = Rect.fromCenter(
      center: drawable.at + Offset(sprite.offsetX, sprite.offsetY),
      width: w,
      height: h,
    );
    canvas.drawImageRect(atlas.image, src, dst, Paint());
    return true;
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => true;
}
