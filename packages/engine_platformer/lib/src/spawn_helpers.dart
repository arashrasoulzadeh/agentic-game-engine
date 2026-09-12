import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'components/gravity.dart';
import 'components/platformer_controller.dart';

/// Spawns a fully-wired platformer player: `Position`, `Velocity`,
/// `Collider`, `Gravity`, `PlatformerController`, and — critically — the
/// [input] `InputState` instance attached as a component, so a
/// `PlatformerInputSystem(id)` (which you still add yourself, since
/// system registration order is the caller's call) can read live key
/// presses. Pass [atlasId]/[spriteRegion] to also attach a `Sprite`.
///
/// This is the "moving"/"jumping" setup helper: it replaces the
/// hand-spawned entity + component boilerplate every platformer needs
/// for its player, without hiding *how* movement/jump actually work —
/// you still register `GravitySystem`/`PlatformerSystem`or
/// `TileCollisionSystem`/`JumpSystem`/`PlatformerInputSystem` yourself,
/// in the order their doc comments describe.
EntityId spawnPlayer(
  World world, {
  required double x,
  required double y,
  required InputState input,
  double radius = 12,
  double jumpSpeed = 500,
  double gravityScale = 1,
  String? atlasId,
  String? spriteRegion,
}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<Velocity>().set(id, Velocity(0, 0));
  world.storeOf<Collider>().set(id, Collider(radius));
  world.storeOf<Gravity>().set(id, Gravity(scale: gravityScale));
  world.storeOf<PlatformerController>().set(
        id,
        PlatformerController(jumpSpeed: jumpSpeed),
      );
  world.storeOf<InputState>().set(id, input);
  if (atlasId != null && spriteRegion != null) {
    world.storeOf<Sprite>().set(id, Sprite(atlasId, spriteRegion));
  }
  return id;
}

/// Spawns an AI-driven enemy: `Position`, `Velocity`, `Collider`, and an
/// `AIState` referencing [behaviorId] (register the actual `Behavior`
/// yourself via a `BehaviorRegistry` — see `PatrolBehavior`/
/// `FollowBehavior` for ready-made ones, or write your own).
///
/// Pass [affectedByGravity] for an enemy that should fall/land like the
/// player (needs `GravitySystem`/`PlatformerSystem`/`TileCollisionSystem`
/// registered same as the player); leave it false for one that just
/// moves horizontally along a fixed line (e.g. a simple ground patroller
/// that's already positioned on the ground).
EntityId spawnEnemy(
  World world, {
  required double x,
  required double y,
  required String behaviorId,
  double radius = 12,
  bool affectedByGravity = false,
  double gravityScale = 1,
  Map<String, dynamic>? memory,
  String? atlasId,
  String? spriteRegion,
}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<Velocity>().set(id, Velocity(0, 0));
  world.storeOf<Collider>().set(id, Collider(radius));
  world.storeOf<AIState>().set(id, AIState(behaviorId, memory: memory));
  if (affectedByGravity) {
    world.storeOf<Gravity>().set(id, Gravity(scale: gravityScale));
    world.storeOf<PlatformerController>().set(id, PlatformerController());
  }
  if (atlasId != null && spriteRegion != null) {
    world.storeOf<Sprite>().set(id, Sprite(atlasId, spriteRegion));
  }
  return id;
}
