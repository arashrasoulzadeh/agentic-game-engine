import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'physics/attack_system.dart';
import 'physics/dash_system.dart';
import 'rendering/facing_system.dart';
import 'physics/gravity_system.dart';
import 'ui/health_hud_system.dart';
import 'logic/health_system.dart';
import 'physics/hitstun_system.dart';
import 'physics/jump_system.dart';
import 'physics/ladder_system.dart';
import 'physics/ledge_grab_system.dart';
import 'rendering/movement_animation_system.dart';
import 'rendering/jump_animation_system.dart';
import 'physics/platformer_input_system.dart';
import 'physics/platformer_system.dart';
import 'logic/projectile_system.dart';
import 'physics/tile_collision_system.dart';
import 'physics/water_physics_system.dart';

/// Registers every system a platformer needs, in the one order that's
/// actually correct — the single call this package exists to make
/// possible, replacing ~10 hand-written `world.addSystem(...)` calls a
/// game would otherwise have to get right itself. Getting this order
/// wrong is a real, easy-to-make mistake: see `JumpSystem`'s doc
/// comment for the bug it caused the one time this repo's own sample
/// game got it wrong.
///
/// Pass [player] to wire up `PlatformerInputSystem` for that entity,
/// [additionalPlayers] for local multiplayer (each gets its own input, ladder and
/// ledge-grab system, reading that entity's own `InputState` -- pair with
/// `SplitScreenView` in `engine_flutter`),
/// and/or [behaviors] to run `AISystem` for AI-controlled entities
/// (patrol/follow enemies, etc.) — both optional, since not every game
/// screen has both a controllable player and AI enemies. Set
/// [includeAnimation] to false if you're not using `Sprite`/
/// `MovementAnimationSet` at all (e.g. a headless test world). Also
/// includes `JumpAnimationSystem`, a no-op for any entity without a
/// `JumpAnimationSet`, so this costs nothing for a game only using
/// `MovementAnimationSet.jump`'s plain single-clip jump.
///
/// Includes `HealthSystem` (ticks down `Health.invincibleSeconds` —
/// harmless even if nothing in your game has a `Health` component yet),
/// `HitstunSystem` (ticks down `PlatformerController.hitstunSeconds`,
/// same reasoning), `HealthHudSystem` (syncs any `HudBar` wired up via
/// `spawnHealthHudBar`/`HealthHudLink` — same "harmless if unused"
/// reasoning), `HitFlashSystem` (syncs `Sprite.tintArgb` from any
/// `HitFlash` — `damageEntity` calls `flashHit` when amount > 0; no-op
/// without the component), `ProjectileSystem` (ages/expires
/// `Projectile`s, same reasoning again), and `AttackSystem` (fires any
/// entity's `Weapon` on its `"attack"` action or a directly-set
/// `Weapon.attackRequested` -- harmless with no `Weapon` components in
/// the world, same reasoning). Damage/death/respawn themselves, and
/// projectile-vs-target damage (`installProjectileDamage`, needed for
/// melee and ranged `Weapon`s since both spawn a `Projectile` under the
/// hood -- see `AttackSystem`'s doc comment), are helpers you call
/// explicitly (`damageEntity`, `dealDamageOnTouch`, `respawnOnDeath`,
/// `installProjectileDamage`), not part of this pack, so *when*/*what*
/// takes damage stays visible in game code.
///
/// If you need a system not covered here (a custom input system, a
/// score system, whatever your game needs), just call
/// `world.addSystem(...)` for it yourself before or after this —
/// this doesn't own the whole system list, only the platformer-genre
/// part of it.
void installPlatformerSystems(
  World world, {
  EntityId? player,
  List<EntityId> additionalPlayers = const [],
  BehaviorRegistry? behaviors,
  bool includeAnimation = true,
}) {
  final players = [if (player != null) player, ...additionalPlayers];
  for (final p in players) {
    world.addSystem(PlatformerInputSystem(p));
  }
  if (behaviors != null) {
    world.addSystem(AISystem(behaviors));
  }
  world.addSystem(GravitySystem());
  world.addSystem(MovementSystem());
  world.addSystem(PlatformerSystem());
  world.addSystem(TileCollisionSystem());
  world.addSystem(WaterPhysicsSystem());
  world.addSystem(JumpSystem());
  for (final p in players) {
    world.addSystem(LadderSystem(p));
    world.addSystem(LedgeGrabSystem(p));
  }
  world.addSystem(DashSystem());
  world.addSystem(CollisionSystem());
  world.addSystem(HealthSystem());
  world.addSystem(HitstunSystem());
  world.addSystem(HealthHudSystem());
  world.addSystem(HitFlashSystem());
  world.addSystem(ProjectileSystem());
  world.addSystem(AttackSystem());
  if (includeAnimation) {
    world.addSystem(FacingSystem());
    world.addSystem(MovementAnimationSystem());
    world.addSystem(JumpAnimationSystem());
    world.addSystem(AnimationSystem());
    world.addSystem(AnimationTransitionSystem());
  }
}
