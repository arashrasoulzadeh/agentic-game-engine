import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'components/gravity.dart';
import 'components/movement_animation_set.dart';
import 'components/platformer_controller.dart';

/// Spawns a fully-wired platformer player: `Position`, `Velocity`,
/// `Collider`, `Gravity`, `PlatformerController`, and — critically — the
/// [input] `InputState` instance attached as a component, so a
/// `PlatformerInputSystem(id)` (which you still add yourself, since
/// system registration order is the caller's call — or let
/// `installPlatformerSystems` handle it) can read live key presses.
/// Pass [atlasId]/[spriteRegion] to also attach a `Sprite`, and
/// [animations] (e.g. from `MovementAnimationSet.fromSequences`) to
/// wire up idle/walk/jump switching in the same call.
///
/// This is the "moving"/"jumping"/character setup helper: it replaces
/// the hand-spawned entity + component boilerplate every platformer
/// needs for its player, without hiding *how* movement/jump actually
/// work — see `installPlatformerSystems` for the systems that make
/// this component data actually do something.
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
  MovementAnimationSet? animations,
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
  if (animations != null) {
    world.storeOf<MovementAnimationSet>().set(id, animations);
    world.storeOf<AnimationState>().set(id, AnimationState(animations.idle));
  }
  return id;
}

/// Spawns an AI-driven enemy: `Position`, `Velocity`, `Collider`, and an
/// `AIState` referencing [behaviorId] (register the actual `Behavior`
/// yourself via a `BehaviorRegistry` — see `PatrolBehavior`/
/// `FollowBehavior` for ready-made ones, or write your own). Pass
/// [animations] the same way as `spawnPlayer` for idle/walk switching.
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
  MovementAnimationSet? animations,
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
  if (animations != null) {
    world.storeOf<MovementAnimationSet>().set(id, animations);
    world.storeOf<AnimationState>().set(id, AnimationState(animations.idle));
  }
  return id;
}
