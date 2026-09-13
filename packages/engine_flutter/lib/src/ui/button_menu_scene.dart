import 'dart:ui' show Offset;

import 'package:engine_core/engine_core.dart';

import '../logic/scene.dart';
import '../rendering/sprite_atlas.dart';
import 'menu_button_atlas.dart';

/// One button in a `ButtonMenuScene`: what it says, and the id its tap
/// reports to `ButtonMenuScene.onButtonPressed`. Plain data — an agent
/// generating a new menu only ever needs to produce a list of these
/// plus a `switch` over the ids, never touch `World`/`Sprite`/`Collider`
/// directly.
class MenuButtonSpec {
  final String label;
  final String actionId;
  const MenuButtonSpec({required this.label, required this.actionId});
}

/// A ready-made ECS menu: give it a list of buttons, handle one action
/// id, done. Handles everything mechanical a `Scene`-based menu
/// otherwise repeats by hand (spawning each button entity, building its
/// atlas, hit-testing taps against `Button` components) — see
/// `MainMenuScene`/`PauseMenuScene` in the sample game for the intended
/// shape of a subclass: override [buttons] and [onButtonPressed], done.
///
/// Buttons stack vertically, centered on the world, in [buttons] order.
/// Override [populate] too (calling `super.populate` first) if a menu
/// needs more than buttons — background art, a title, a `TileMap` — the
/// base implementation only ever adds the button entities.
abstract class ButtonMenuScene extends Scene {
  /// The `GameState` this menu was populated with — set by `populate`
  /// before [buttons]/[onButtonPressed] can run, so a subclass can read
  /// it (e.g. to show a coin count in a button's label) or write to it
  /// (e.g. a "New Game" button resetting progress) without needing its
  /// own field for something `Scene.populate` already receives.
  late final GameState state;

  /// The buttons this menu shows, top to bottom. Called after [state]
  /// is set, so labels may depend on it (e.g. `'PLAY (${state.data['coins']})'`).
  List<MenuButtonSpec> buttons();

  /// Called with the `actionId` of whichever button was tapped —
  /// implement this instead of overriding `handleTap`/`hitTestButton`
  /// yourself. Typically a `switch` that calls
  /// `scenes.loadScene(...)`/`scenes.pushOverlay(...)`/`scenes.popOverlay()`.
  void onButtonPressed(String actionId, SceneController scenes);

  /// Vertical gap between button centers. Override for a denser or
  /// more spread-out menu; button height itself is fixed at
  /// [kMenuButtonHeight] (see `menu_button_atlas.dart`).
  double get buttonSpacing => kMenuButtonHeight + 16;

  /// A menu is tap-driven, not movement/action-driven — the
  /// joystick/jump-style buttons `Game.onScreenButtons` describes would
  /// just float uselessly over every `ButtonMenuScene` otherwise. See
  /// `Scene.showOnScreenControls`.
  @override
  bool get showOnScreenControls => false;

  /// A menu isn't a lit game world — it shouldn't darken just because
  /// the game's gameplay scenes use `Light2D` lighting via
  /// `GameConfig.ambientBrightness`. Found needed live: `test_game`'s
  /// main menu darkened along with gameplay before this override
  /// existed. See `Scene.ambientBrightness`.
  @override
  double get ambientBrightness => 1.0;

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    this.state = state;
    final specs = buttons();
    final startY = world.height / 2 - (specs.length - 1) * buttonSpacing / 2;
    for (var i = 0; i < specs.length; i++) {
      spawnMenuButton(
        world,
        position: Offset(world.width / 2, startY + i * buttonSpacing),
        label: specs[i].label,
        actionId: specs[i].actionId,
      );
    }
  }

  @override
  Future<AtlasRegistry> loadAssets() async {
    final atlasRegistry = AtlasRegistry();
    atlasRegistry.register(
      kMenuButtonAtlasId,
      await buildMenuButtonAtlas(buttons().map((b) => b.label).toList()),
    );
    return atlasRegistry;
  }

  @override
  void handleTap(World world, SceneController scenes, Offset worldPosition) {
    final hit = hitTestButton(world, worldPosition.dx, worldPosition.dy);
    if (hit == null) return;
    final actionId = world.storeOf<Button>().get(hit)?.actionId;
    if (actionId != null) onButtonPressed(actionId, scenes);
  }
}
