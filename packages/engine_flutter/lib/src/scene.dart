import 'dart:ui' show Offset;

import 'package:engine_core/engine_core.dart';

import 'camera.dart';
import 'sprite_atlas.dart';

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
  /// `Future<void>` (not `void`) because loading a level from a bundled
  /// JSON asset — `rootBundle.loadString` + `Level.loadInto` — is
  /// itself async; a scene with nothing to await can just mark this
  /// `async` with no `await` in the body, or return a completed Future.
  Future<void> populate(World world, SceneController scenes);

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
