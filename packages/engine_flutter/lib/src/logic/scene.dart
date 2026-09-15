import 'dart:ui' show Offset;

import 'package:engine_core/engine_core.dart';

import '../rendering/camera.dart';
import '../rendering/sprite_atlas.dart';

/// One level/room a `Game` can be showing. `GameRunner` builds a fresh
/// `World` per scene (not a bulk-clear of the previous one, so no
/// system/entity state can leak across a switch), registers core +
/// Flutter components on it, then calls these in order: `populate`,
/// `loadAssets`, `createCamera`.
///
/// A game with only one level implements a single `Scene` and returns
/// it from `Game.createInitialScene()`. A game with rooms/doors
/// implements one `Scene` per room and calls
/// `scenes.loadScene(NextRoomScene())` from inside `populate` (typically
/// from a collision handler or `Behavior` registered there) to switch.
abstract class Scene {
  /// Adds systems and spawns entities on [world] — the same
  /// responsibility `Game.populateWorld` used to have. [scenes] is this
  /// scene's handle for triggering a switch to another `Scene` (e.g. on
  /// a door/room-exit collision); stash it in a closure/`Behavior` if
  /// the trigger fires later than `populate` itself.
  ///
  /// [state] is the one `GameState` instance `GameRunner` keeps for the
  /// whole running game — read whatever this scene needs from it (coins
  /// collected so far, which rooms are unlocked) and write back before
  /// switching away, since `loadScene` always starts the next scene from
  /// a blank `World` (see `SceneController.loadScene`) but [state] is
  /// the one thing that survives that swap.
  ///
  /// `Future<void>` (not `void`) because loading a level from a bundled
  /// JSON asset — `rootBundle.loadString` + `Level.loadInto` — is
  /// itself async; a scene with nothing to await can just mark this
  /// `async` with no `await` in the body, or return a completed Future.
  Future<void> populate(World world, SceneController scenes, GameState state);

  /// Loads sprite atlases (or other async setup) before the scene's
  /// first frame. Defaults to an empty registry for a scene with no
  /// sprites yet.
  Future<AtlasRegistry> loadAssets() async => AtlasRegistry();

  /// Defaults to a camera centered on the world. Override to start
  /// somewhere else or follow a specific entity from frame one.
  Camera createCamera(World world) =>
      Camera(x: world.width / 2, y: world.height / 2);

  /// Returns null (static camera) by default — override to make the
  /// camera follow a specific entity (typically the player) each frame.
  EntityId? cameraFollowEntity(World world) => null;

  /// Whether `GameRunner` overlays the joystick/button touch controls
  /// (see `Game.onScreenButtons`/`OnScreenControls`) while this scene is
  /// showing. Defaults to `true` — a gameplay scene needs them. A
  /// tap-driven scene with no movement/action to control (any
  /// `ButtonMenuScene` — a title screen, a pause menu) overrides this
  /// to `false`, since a joystick/jump button floating over a menu is
  /// visual clutter that does nothing there. `GameRunner` also hides
  /// controls whenever an overlay (`SceneController.pushOverlay`) is
  /// active, regardless of what the base scene underneath returns here
  /// — the base scene is frozen then, so its controls would do nothing
  /// either.
  bool get showOnScreenControls => true;

  /// Overrides `GameConfig.ambientBrightness` (see `EngineView`'s doc
  /// comment on it) for just this scene — `null` (default) means "use
  /// the game's own global setting." A gameplay scene using `Light2D`
  /// lighting typically leaves this alone (that's what the global
  /// config value is for); a menu/HUD-only scene that shouldn't darken
  /// just because the rest of the game uses lighting overrides this to
  /// `1.0`. Found needed live: `test_game`'s main menu darkened along
  /// with gameplay before this existed, since `ambientBrightness` had
  /// no way to be "off" for one specific scene.
  double? get ambientBrightness => null;

  /// Drives `EngineView.dayNightCycle` for just this scene — `null`
  /// (default) means "no time-of-day/weather lighting," identical to
  /// how this engine behaved before `DayNightCycle` existed. A
  /// gameplay scene that wants a living, cyclical sky (unlike the
  /// fixed, scene-authored [ambientBrightness] override above) returns
  /// its own `DayNightCycle` instance here — `EngineView` advances it
  /// once per tick automatically. A menu/HUD-only scene typically
  /// leaves this `null` for the same reason it overrides
  /// [ambientBrightness] to `1.0` instead of inheriting one.
  DayNightCycle? get dayNightCycle => null;

  /// Called on every tap/click with its position already converted to
  /// world coordinates (see `Camera.screenToWorld`) — how an ECS menu
  /// (`Button`-tagged entities) or an in-world tap target (a door)
  /// reacts to a pointer. Does nothing by default; a gameplay scene with
  /// no tap-driven UI doesn't need to override this at all. Combine with
  /// `hitTestButton(world, worldPosition.dx, worldPosition.dy)` for the
  /// common "which button did they tap" case.
  void handleTap(World world, SceneController scenes, Offset worldPosition) {}
}

/// Handed to every `Scene.populate` call so in-scene logic can switch to
/// a different `Scene` at runtime (a door, a screen-edge trigger, a
/// level-complete condition), or pause it under an overlay (a pause
/// menu) without losing its state. `GameRunner` owns the one instance
/// for its lifetime and rebinds it to whichever scene is currently
/// loading, so a `Behavior`/event handler captured from an old scene
/// that calls one of these after the switch still reaches a live
/// `GameRunner`.
class SceneController {
  void Function(Scene next)? _loadScene;
  void Function(Scene overlay)? _pushOverlay;
  void Function()? _popOverlay;

  /// Wired up by `GameRunner`; not for a game to call directly.
  void attach({
    required void Function(Scene next) loadScene,
    required void Function(Scene overlay) pushOverlay,
    required void Function() popOverlay,
  }) {
    _loadScene = loadScene;
    _pushOverlay = pushOverlay;
    _popOverlay = popOverlay;
  }

  /// Tears down the current scene's `World` and loads [next] in its
  /// place: a fresh `World` is built, core + Flutter components are
  /// re-registered, then [next]'s `populate`/`loadAssets`/`createCamera`
  /// run before it's swapped in. No entity/component state carries over
  /// from the previous scene — use [pushOverlay] instead when the point
  /// is to come back to exactly where play left off (a pause menu),
  /// since `loadScene` always starts from a blank `World`.
  void loadScene(Scene next) {
    final loadScene = _loadScene;
    if (loadScene == null) {
      throw StateError(
          'SceneController.loadScene called before it was attached to a running GameRunner');
    }
    loadScene(next);
  }

  /// Freezes the current scene in place (its `World` keeps existing,
  /// just stops ticking) and layers [overlay] — its own small `World`,
  /// populated/rendered independently — on top of it, dimmed. Taps route
  /// to [overlay] only while it's active, so the paused scene underneath
  /// can't be accidentally interacted with. This is the engine's one
  /// pause mechanism; what the overlay actually shows (which buttons,
  /// what they do) is entirely up to the `Scene` a game passes in — see
  /// `Scene.handleTap` — the engine only owns freeze/layer/route, never
  /// the menu's content.
  ///
  /// Call [popOverlay] (typically from the overlay's own "Resume"
  /// button) to remove it and let the paused scene keep going exactly
  /// where it left off.
  void pushOverlay(Scene overlay) {
    final pushOverlay = _pushOverlay;
    if (pushOverlay == null) {
      throw StateError(
          'SceneController.pushOverlay called before it was attached to a running GameRunner');
    }
    pushOverlay(overlay);
  }

  /// Removes the current overlay (if any) and resumes the scene beneath
  /// it. A no-op if no overlay is active.
  void popOverlay() {
    final popOverlay = _popOverlay;
    if (popOverlay == null) {
      throw StateError(
          'SceneController.popOverlay called before it was attached to a running GameRunner');
    }
    popOverlay();
  }
}
