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
///
/// By default (leave [atlasId]/[region] `null`) a button renders via
/// the engine's own runtime-generated flat rounded-rect atlas (see
/// `buildMenuButtonAtlas`) — no bundled art required, the original
/// behavior. Set both [atlasId] and [region] to render from real
/// sprite-sheet art instead (a game-loaded `AtlasRegistry` entry,
/// registered the same way any other `Sprite` atlas is): [scaleX]/
/// [scaleY] (default `1`, native pixel size) scale that art like any
/// other `Sprite`; [width]/[height] independently size the button's
/// rectangular hit area (`ButtonHitBox` — see its own doc comment for
/// why a rectangle over a circle), defaulting to [kMenuButtonWidth]/
/// [kMenuButtonHeight] if omitted. A spec with only one of [atlasId]/
/// [region] set is a mistake `ButtonMenuScene.populate` asserts
/// against rather than silently drawing nothing.
class MenuButtonSpec {
  final String label;
  final String actionId;
  final String? atlasId;
  final String? region;
  final double? width;
  final double? height;
  final double scaleX;
  final double scaleY;

  const MenuButtonSpec({
    required this.label,
    required this.actionId,
    this.atlasId,
    this.region,
    this.width,
    this.height,
    this.scaleX = 1,
    this.scaleY = 1,
  }) : assert(
          (atlasId == null) == (region == null),
          'atlasId and region must be set together, or not at all',
        );

  /// Whether this spec supplies its own art instead of using the
  /// engine's generated flat-rect button.
  bool get hasCustomArt => atlasId != null;
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
      final spec = specs[i];
      spawnMenuButton(
        world,
        position: Offset(world.width / 2, startY + i * buttonSpacing),
        label: spec.label,
        actionId: spec.actionId,
        atlasId: spec.atlasId,
        region: spec.region,
        width: spec.width,
        height: spec.height,
        scaleX: spec.scaleX,
        scaleY: spec.scaleY,
      );
    }
  }

  @override
  Future<AtlasRegistry> loadAssets() async {
    final atlasRegistry = AtlasRegistry();
    // Only the specs still using the generated rect (no custom art)
    // need a region in the runtime-built atlas -- a spec with its own
    // atlasId/region draws from whatever the game itself registers
    // (this method is meant to be overridden, calling super.loadAssets()
    // first, to add that -- see MainMenuScene in the sample game).
    final generatedLabels =
        buttons().where((b) => !b.hasCustomArt).map((b) => b.label).toList();
    if (generatedLabels.isNotEmpty) {
      atlasRegistry.register(kMenuButtonAtlasId, await buildMenuButtonAtlas(generatedLabels));
    }
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
