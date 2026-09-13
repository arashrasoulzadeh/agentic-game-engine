import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'physics/gravity.dart';
import 'logic/health.dart';
import 'logic/inventory.dart';
import 'logic/last_checkpoint.dart';
import 'rendering/movement_animation_set.dart';
import 'physics/platformer_controller.dart';

/// Position/Velocity/Collider, the physical minimum every spawned
/// character needs regardless of player/enemy — shared so the two
/// spawn helpers below can't drift on it.
void _attachBody(World world, EntityId id, double x, double y, double radius) {
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<Velocity>().set(id, Velocity(0, 0));
  world.storeOf<Collider>().set(id, Collider(radius));
}

/// Attaches a `Sprite` only if both [atlasId] and [spriteRegion] are
/// given — shared so "sprite is optional, both-or-neither" isn't
/// reimplemented (and potentially left inconsistent) per spawn helper.
void _attachSprite(World world, EntityId id, String? atlasId, String? spriteRegion) {
  if (atlasId != null && spriteRegion != null) {
    world.storeOf<Sprite>().set(id, Sprite(atlasId, spriteRegion));
  }
}

/// Attaches `MovementAnimationSet` + an initial `AnimationState` on the
/// idle clip, if [animations] is given.
void _attachAnimations(World world, EntityId id, MovementAnimationSet? animations) {
  if (animations != null) {
    world.storeOf<MovementAnimationSet>().set(id, animations);
    world.storeOf<AnimationState>().set(id, AnimationState(animations.idle));
  }
}

/// Attaches `Health` (full at spawn), if [maxHealth] is given.
void _attachHealth(World world, EntityId id, double? maxHealth) {
  if (maxHealth != null) {
    world.storeOf<Health>().set(id, Health(current: maxHealth, max: maxHealth));
  }
}

/// Spawns a fully-wired platformer player: `Position`, `Velocity`,
/// `Collider`, `Gravity`, `PlatformerController`, and — critically — the
/// [input] `InputState` instance attached as a component, so a
/// `PlatformerInputSystem(id)` (which you still add yourself, since
/// system registration order is the caller's call — or let
/// `installPlatformerSystems` handle it) can read live key presses.
/// Pass [atlasId]/[spriteRegion] to also attach a `Sprite`, and
/// [animations] (e.g. from `MovementAnimationSet.fromSequences`) to
/// wire up idle/walk/jump switching in the same call. Pass [maxHealth]
/// to also attach `Health` (full at spawn) and a `LastCheckpoint`
/// seeded at the spawn position, ready for `respawnPlayer`/
/// `respawnOnDeath` without a separate setup call. Pass
/// [startingInventory] to also attach an `Inventory` pre-populated with
/// those item counts (e.g. `{'coin': 0}`), ready for `collectItem`/
/// `dealPickupOnTouch`.
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
  double? maxHealth,
  Map<String, int>? startingInventory,
}) {
  final id = world.spawn();
  _attachBody(world, id, x, y, radius);
  world.storeOf<Gravity>().set(id, Gravity(scale: gravityScale));
  world.storeOf<PlatformerController>().set(
        id,
        PlatformerController(jumpSpeed: jumpSpeed),
      );
  world.storeOf<InputState>().set(id, input);
  _attachSprite(world, id, atlasId, spriteRegion);
  _attachAnimations(world, id, animations);
  _attachHealth(world, id, maxHealth);
  if (maxHealth != null) {
    world.storeOf<LastCheckpoint>().set(id, LastCheckpoint(x, y));
  }
  if (startingInventory != null) {
    world.storeOf<Inventory>().set(id, Inventory(Map.of(startingInventory)));
  }
  return id;
}

/// Spawns an AI-driven enemy: `Position`, `Velocity`, `Collider`, and an
/// `AIState` referencing [behaviorId] (register the actual `Behavior`
/// yourself via a `BehaviorRegistry` — see `PatrolBehavior`/
/// `FollowBehavior` for ready-made ones, or write your own). Pass
/// [animations] the same way as `spawnPlayer` for idle/walk switching,
/// and [maxHealth] to make the enemy damageable via `damageEntity`.
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
  double? maxHealth,
}) {
  final id = world.spawn();
  _attachBody(world, id, x, y, radius);
  world.storeOf<AIState>().set(id, AIState(behaviorId, memory: memory));
  if (affectedByGravity) {
    world.storeOf<Gravity>().set(id, Gravity(scale: gravityScale));
    world.storeOf<PlatformerController>().set(id, PlatformerController());
  }
  _attachSprite(world, id, atlasId, spriteRegion);
  _attachAnimations(world, id, animations);
  _attachHealth(world, id, maxHealth);
  return id;
}
