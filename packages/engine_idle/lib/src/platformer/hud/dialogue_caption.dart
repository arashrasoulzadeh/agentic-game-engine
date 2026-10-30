import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart'
    as eng
    show Sprite, Text, TextAlignment;

import 'hud_layout.dart';

/// A line of on-screen text that types itself in, holds, and erases — built
/// on the engine's dialogue system rather than a hand-rolled timer.
///
/// [show] wraps the line in a one-node `DialogueGraph` and lets a
/// `DialogueRunner` reveal it (its typewriter, honouring the node's
/// `typewriterDuration`); [hide] erases it backwards, faster than it typed.
/// Drive it with [update] every tick. The text is a world-space `Text` at
/// the position and style of a [HudTextStyle] — in world units, so a layout
/// can centre it on the world whatever the window size.
class DialogueCaption {
  /// With [backdropAtlasId], a panel of [backdropWidth] x [backdropHeight]
  /// world units opens behind the text as it appears and closes as it goes.
  DialogueCaption.spawn(
    World world, {
    required this.style,
    String? backdropAtlasId,
    double backdropWidth = 0,
    double backdropHeight = 0,
    double backdropSourceWidth = 128,
    double backdropSourceHeight = 78,
  }) : _backdropW = backdropWidth / backdropSourceWidth,
       _backdropH = backdropHeight / backdropSourceHeight {
    if (backdropAtlasId != null) {
      _backdrop = world.spawn();
      world.storeOf<Position>().set(_backdrop!, Position(style.x, style.y));
      world.storeOf<eng.Sprite>().set(
        _backdrop!,
        eng.Sprite(backdropAtlasId, 'full', scaleX: 0, scaleY: 0, zIndex: 119),
      );
    }
    _entity = world.spawn();
    world.storeOf<Position>().set(_entity, Position(style.x, style.y));
    world.storeOf<eng.Text>().set(
      _entity,
      eng.Text(
        '',
        fontSize: style.fontSize,
        colorArgb: style.colorArgb,
        align: eng.TextAlignment.center,
        // World space: `x`/`y` are world units and the text scales with the
        // camera, so (world.width / 2, world.height / 2) is the true centre
        // at any window size. (Screen-space text positions are raw pixels.)
        screenSpace: false,
        zIndex: 120,
        maxWidth: style.maxWidth,
        rtl: style.rtl,
      ),
    );
  }

  final HudTextStyle style;

  /// Characters revealed per second while typing in.
  static const typeCharsPerSecond = 60.0;

  /// Erasing runs this many times faster than typing.
  static const eraseSpeedUp = 3.0;

  late final EntityId _entity;
  EntityId? _backdrop;
  final double _backdropW;
  final double _backdropH;
  double _open = 0;
  DialogueRunner? _runner;
  String _full = '';
  bool _erasing = false;
  double _eraseProgress = 0;

  /// True while any text is on screen (typing, holding or erasing).
  bool get visible => _full.isNotEmpty;

  /// The characters currently on screen.
  String get shown => _shown;
  String _shown = '';

  /// Types [text] in (replacing whatever is showing).
  void show(World world, String text) {
    _full = text;
    _erasing = false;
    _eraseProgress = 0;
    if (text.isEmpty) {
      _runner = null;
      _set(world, '');
      return;
    }
    const key = 'caption';
    final runner = DialogueRunner(
      graph: DialogueGraph(
        nodes: {
          key: DialogueNode(
            id: key,
            textKey: key,
            typewriterDuration: text.length / typeCharsPerSecond,
            choices: const [],
          ),
        },
        startNodeId: key,
      ),
      stringTable: StringTable({
        key: {'en': text},
      }),
    );
    runner.reset();
    _runner = runner;
    _set(world, '');
  }

  /// Erases the text with a quick reverse typewriter.
  void hide() {
    if (_full.isEmpty || _erasing) return;
    _erasing = true;
    _eraseProgress = 0;
    _runner = null;
  }

  void update(World world, double dt) {
    _animateBackdrop(world, dt);
    if (_full.isEmpty) return;
    if (_erasing) {
      _eraseProgress += dt * typeCharsPerSecond * eraseSpeedUp;
      final left = _full.length - _eraseProgress.floor();
      if (left <= 0) {
        _full = '';
        _set(world, '');
      } else {
        _set(world, _full.substring(0, left));
      }
      return;
    }
    final runner = _runner;
    if (runner == null) return;
    final view = WorldView(world);
    runner.updateTypewriter(dt, view);
    _set(world, runner.visibleText(view) ?? _full);
  }

  /// Opens the panel while text is up, closes it when it is gone.
  void _animateBackdrop(World world, double dt) {
    final id = _backdrop;
    if (id == null) return;
    final wantOpen = _full.isNotEmpty && !_erasing;
    _open = (_open + (wantOpen ? 1 : -1) * dt * 5).clamp(0.0, 1.0);
    // Ease-out so it snaps open and settles.
    final k = 1 - (1 - _open) * (1 - _open);
    world.storeOf<eng.Sprite>().get(id)
      ?..scaleX = _backdropW * k
      ..scaleY = _backdropH * k;
  }

  void _set(World world, String text) {
    _shown = text;
    world.storeOf<eng.Text>().get(_entity)?.text = text;
  }
}
