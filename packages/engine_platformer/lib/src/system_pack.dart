import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

import 'physics/dash_system.dart';
import 'rendering/facing_system.dart';
import 'physics/gravity_system.dart';
import 'ui/health_hud_system.dart';
import 'logic/health_system.dart';
import 'physics/hitstun_system.dart';
import 'physics/jump_system.dart';
import 'rendering/movement_animation_system.dart';
import 'physics/platformer_input_system.dart';
import 'physics/platformer_system.dart';
import 'logic/projectile_system.dart';
import 'physics/tile_collision_system.dart';

/// Registers every system a platformer needs, in the one order that's
/// actually correct — the single call this package exists to make
/// possible, replacing ~10 hand-written `world.addSystem(...)` calls a
/// game would otherwise have to get right itself. Getting this order
/// wrong is a real, easy-to-make mistake: see `JumpSystem`'s doc
/// comment for the bug it caused the one time this repo's own sample
/// game got it wrong.
///
/// Pass [player] to wire up `PlatformerInputSystem` for that entity,
/// and/or [behaviors] to run `AISystem` for AI-controlled entities
/// (patrol/follow enemies, etc.) — both optional, since not every game
/// screen has both a controllable player and AI enemies. Set
/// [includeAnimation] to false if you're not using `Sprite`/
/// `MovementAnimationSet` at all (e.g. a headless test world).
///
/// Includes `HealthSystem` (ticks down `Health.invincibleSeconds` —
/// harmless even if nothing in your game has a `Health` component yet),
/// `HitstunSystem` (ticks down `PlatformerController.hitstunSeconds`,
/// same reasoning), `HealthHudSystem` (syncs any `HudBar` wired up via
/// `spawnHealthHudBar`/`HealthHudLink` — same "harmless if unused"
/// reasoning), and `ProjectileSystem` (ages/expires `Projectile`s, same
/// reasoning again). Damage/death/respawn themselves, and
/// projectile-vs-target damage (`installProjectileDamage`), are helpers
/// you call explicitly (`damageEntity`, `dealDamageOnTouch`,
/// `respawnOnDeath`, `installProjectileDamage`), not part of this pack,
/// so *when*/*what* takes damage stays visible in game code.
///
/// If you need a system not covered here (a custom input system, a
/// score system, whatever your game needs), just call
/// `world.addSystem(...)` for it yourself before or after this —
/// this doesn't own the whole system list, only the platformer-genre
/// part of it.
void installPlatformerSystems(
  World world, {
  EntityId? player,
  BehaviorRegistry? behaviors,
  bool includeAnimation = true,
}) {
  if (player != null) {
    world.addSystem(PlatformerInputSystem(player));
  }
  if (behaviors != null) {
    world.addSystem(AISystem(behaviors));
  }
  world.addSystem(GravitySystem());
  world.addSystem(MovementSystem());
  world.addSystem(PlatformerSystem());
  world.addSystem(TileCollisionSystem());
  world.addSystem(JumpSystem());
  world.addSystem(DashSystem());
  world.addSystem(CollisionSystem());
  world.addSystem(HealthSystem());
  world.addSystem(HitstunSystem());
  world.addSystem(HealthHudSystem());
  world.addSystem(ProjectileSystem());
  if (includeAnimation) {
    world.addSystem(FacingSystem());
    world.addSystem(MovementAnimationSystem());
    world.addSystem(AnimationSystem());
  }
}
