import 'dart:math';

import '../ai/ai_system.dart';
import '../physics/collision_system.dart';
import '../physics/movement_system.dart';
import '../physics/pushable_system.dart';
import '../physics/tile_animation_system.dart';
import '../rendering/particle_system.dart';
import '../rendering/tween_system.dart';
import 'behavior.dart';
import 'countdown_timer.dart';
import 'world.dart';

/// Ready-made groups of systems, added in a verified order with one call.
///
/// Genre-specific presets already exist where the genre's code lives:
/// `installPlatformerSystems` (engine_platformer) and `installStrategySystems`
/// (engine_strategy); their orders are pinned by golden tests. Core cannot
/// depend on them, so this class covers only what is genre-general.
abstract final class SystemPresets {
  /// Adds the genre-general simulation: timers, optional AI, movement,
  /// collision, pushing, tile animation, tweens and particles.
  ///
  /// Pass [behaviors] to also run entity AI (`AIState` components). Particles
  /// use a stream seeded from `world.seed`, so the world stays reproducible.
  /// Components are not registered here: call `registerCoreComponents` first
  /// (or use `GameBuilder`, which does both).
  ///
  /// Order, with phases: `countdownTimer`, `ai` (pre-physics); `movement`
  /// then `collision` then `pushable`, `tileAnimation`, `tween` (physics);
  /// `particles` (late). `collision` declares it runs after `movement` and
  /// `pushable` after `collision`, so `world.validateSystemOrder()` can
  /// confirm nothing was shuffled afterwards.
  static void core(World world, {BehaviorRegistry? behaviors}) {
    world.addSystem(CountdownTimerSystem(), phase: SystemPhase.prePhysics);
    if (behaviors != null) {
      world.addSystem(AISystem(behaviors), phase: SystemPhase.prePhysics);
    }
    world
      ..addSystem(MovementSystem())
      ..addSystem(CollisionSystem(), after: ['movement'])
      ..addSystem(PushableSystem(), after: ['collision'])
      ..addSystem(TileAnimationSystem())
      ..addSystem(TweenSystem())
      ..addSystem(
        ParticleSystem(random: Random(world.seed)),
        phase: SystemPhase.late,
      );
  }
}
