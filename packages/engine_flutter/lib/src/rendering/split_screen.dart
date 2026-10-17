import 'package:engine_core/engine_core.dart' show EntityId, World;
import 'package:flutter/widgets.dart';

import '../input/input.dart';
import 'camera.dart';
import 'engine_view.dart';
import 'sprite_atlas.dart';

/// How to cut the screen for a given number of local players.
enum SplitOrientation {
  /// Pick from the screen shape: side by side when it is wider than tall,
  /// stacked when it is taller (so each player's view stays close to the
  /// screen's own aspect).
  auto,
  sideBySide,
  stacked,
}

/// Where each player's view goes on a screen of [size].
class SplitScreenLayout {
  const SplitScreenLayout._();

  /// One rectangle per player, in player order.
  ///
  /// 1 player fills the screen; 2 split it in half along [orientation]; 3 and 4
  /// use a 2x2 grid (with 3 players the fourth cell is simply left empty, which
  /// is clearer than stretching one view over two cells). [gap] pixels separate
  /// views so a divider can show between them. Counts above 4 throw: more than 4
  /// local views stops being usable on a single screen.
  static List<Rect> rects(
    int players,
    Size size, {
    double gap = 2,
    SplitOrientation orientation = SplitOrientation.auto,
  }) {
    if (players < 1 || players > 4) {
      throw RangeError.range(players, 1, 4, 'players', 'split-screen supports 1 to 4 players');
    }
    final full = Offset.zero & size;
    if (players == 1) return [full];

    if (players == 2) {
      final horizontal = switch (orientation) {
        SplitOrientation.sideBySide => true,
        SplitOrientation.stacked => false,
        SplitOrientation.auto => size.width >= size.height,
      };
      if (horizontal) {
        final w = (size.width - gap) / 2;
        return [Rect.fromLTWH(0, 0, w, size.height), Rect.fromLTWH(w + gap, 0, w, size.height)];
      }
      final h = (size.height - gap) / 2;
      return [Rect.fromLTWH(0, 0, size.width, h), Rect.fromLTWH(0, h + gap, size.width, h)];
    }

    final w = (size.width - gap) / 2;
    final h = (size.height - gap) / 2;
    final cells = [
      Rect.fromLTWH(0, 0, w, h),
      Rect.fromLTWH(w + gap, 0, w, h),
      Rect.fromLTWH(0, h + gap, w, h),
      Rect.fromLTWH(w + gap, h + gap, w, h),
    ];
    return cells.take(players).toList();
  }
}

/// One shared `World` drawn once per local player, each through its own `Camera`
/// following its own entity.
///
/// The simulation is stepped by exactly one view (the first), the rest are
/// non-stepping (`EngineView.stepsWorld`), so the game runs at normal speed no
/// matter how many players are watching. Each player's input lives in their own
/// entity's `InputState` (fed by that player's `InputController`, usually a
/// keyboard for one and gamepads for the rest), which is what lets several
/// platformer players share a world; see `installPlatformerSystems`'s
/// `additionalPlayers`.
class SplitScreenView extends StatelessWidget {
  const SplitScreenView({
    super.key,
    required this.world,
    required this.atlasRegistry,
    required this.cameras,
    required this.followEntities,
    this.inputControllers = const [],
    this.gap = 2,
    this.dividerColor = const Color(0xFF000000),
    this.orientation = SplitOrientation.auto,
    this.backgroundColor = const Color(0xFF000000),
    this.fixedTimestepSeconds,
  }) : assert(cameras.length == followEntities.length, 'one camera and one entity per player');

  final World world;
  final AtlasRegistry atlasRegistry;

  /// One camera per player; their count is the player count.
  final List<Camera> cameras;

  /// The entity each camera follows; null leaves that camera where it is.
  final List<EntityId?> followEntities;

  /// Optional per-player input; only the first non-null controller receives
  /// keyboard events (a keyboard has one focus), the others should be fed by
  /// gamepads.
  final List<InputController?> inputControllers;

  final double gap;
  final Color dividerColor;
  final SplitOrientation orientation;
  final Color backgroundColor;
  final double? fixedTimestepSeconds;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final rects = SplitScreenLayout.rects(cameras.length, size, gap: gap, orientation: orientation);
      var keyboardGiven = false;
      return Stack(children: [
        Positioned.fill(child: ColoredBox(color: dividerColor)),
        for (var i = 0; i < rects.length; i++)
          Positioned.fromRect(
            rect: rects[i],
            child: ClipRect(
              child: EngineView(
                key: ValueKey('split-view-$i'),
                world: world,
                atlasRegistry: atlasRegistry,
                camera: cameras[i],
                cameraFollowEntity: followEntities[i],
                stepsWorld: i == 0,
                backgroundColor: backgroundColor,
                fixedTimestepSeconds: fixedTimestepSeconds,
                inputController: () {
                  final c = i < inputControllers.length ? inputControllers[i] : null;
                  if (c == null || keyboardGiven) return null;
                  keyboardGiven = true;
                  return c;
                }(),
              ),
            ),
          ),
      ]);
    });
  }
}
