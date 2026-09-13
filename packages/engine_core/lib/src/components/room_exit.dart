/// Marks an entity as a room/level transition trigger — a door, a
/// screen-edge zone, a ladder to the next floor. Plain data, the same
/// "reference registered code by id" pattern as `AIState.behaviorId`/
/// `Button.actionId`: [targetSceneId] names a `Scene` the game itself
/// registers ahead of time (there's no way to embed a `Scene` — Flutter
/// rendering/asset-loading code — inside JSON), and [spawnPoint] names
/// where the player should appear there.
///
/// The convention the rest of the engine (`installRoomExitTrigger` in
/// `engine_flutter`) follows: [spawnPoint] matches the `"name"` of an
/// entity in the *destination* level's JSON (see `Level.loadInto`'s
/// named-entity map) — typically just a bare `position`-only entity
/// marking where a door lets the player back out. Needs both a
/// `Position` (where the trigger sits) and a `Collider` (how big its
/// touch zone is) on the same entity, same as `Button`.
class RoomExit {
  String targetSceneId;
  String spawnPoint;

  RoomExit(this.targetSceneId, this.spawnPoint);

  Map<String, dynamic> toJson() => {
        'targetSceneId': targetSceneId,
        'spawnPoint': spawnPoint,
      };

  factory RoomExit.fromJson(Map<String, dynamic> json) => RoomExit(
        json['targetSceneId'] as String,
        json['spawnPoint'] as String,
      );
}
