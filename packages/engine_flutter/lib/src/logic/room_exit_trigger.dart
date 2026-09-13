import 'package:engine_core/engine_core.dart';

import 'scene.dart';

/// Builds the `Scene` a `RoomExit` should switch to. A plain function
/// (not a stored `Scene` instance) so each door only pays to construct
/// its destination when actually walked through, and so the same
/// target can be reached fresh from any number of doors.
typedef SceneFactory = Scene Function();

/// Wires up `RoomExit`-tagged entities so touching one switches to its
/// target scene — the collision-driven counterpart to `ButtonMenuScene`
/// (tap-driven). Call once from a gameplay `Scene.populate`, after
/// `CollisionSystem` is registered (`installPlatformerSystems`/
/// `World.addSystem(CollisionSystem())` already does, depending on your
/// genre) — same ordering requirement as any other
/// `onCollisionInvolving` handler.
///
/// [scenesById] maps `RoomExit.targetSceneId` -> a factory for that
/// `Scene`; a door referencing an id missing from this map throws
/// immediately (a level-authoring mistake, not a runtime condition to
/// swallow). Before switching, the trigger writes the touched
/// `RoomExit.spawnPoint` into `state.data['enteredAt']` — the
/// destination scene reads that back (typically to look up a
/// same-named marker entity in its own level JSON, via
/// `Level.loadInto`'s named-entity map) to know which door the player
/// should appear at, since `loadScene` always starts the next scene
/// from a blank `World` with no memory of where the player came from.
void installRoomExitTrigger(
  World world, {
  required EntityId player,
  required SceneController scenes,
  required GameState state,
  required Map<String, SceneFactory> scenesById,
}) {
  world.onCollisionInvolving(player, (other) {
    final exit = world.storeOf<RoomExit>().get(other);
    if (exit == null) return;

    final factory = scenesById[exit.targetSceneId];
    if (factory == null) {
      throw StateError(
          'RoomExit references unknown scene id "${exit.targetSceneId}" -- '
          'registered ids: ${scenesById.keys}');
    }

    state.data['enteredAt'] = exit.spawnPoint;
    scenes.loadScene(factory());
  });
}
