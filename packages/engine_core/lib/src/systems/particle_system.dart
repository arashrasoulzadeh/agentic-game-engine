import 'dart:math';

import '../components/particle.dart';
import '../components/particle_emitter.dart';
import '../components/position.dart';
import '../components/velocity.dart';
import '../entity.dart';
import '../system.dart';
import '../world.dart';

/// Spawns particles from every `ParticleEmitter` (continuous [rate] and
/// one-shot `burstCount`), then ages and destroys every `Particle`
/// whose lifetime has elapsed. Relies on `MovementSystem` (also
/// registered by you, same as any other system) to actually move
/// spawned particles by the `Velocity` this system gives them —
/// deliberately not duplicated here.
///
/// Pass a seeded [random] in tests for deterministic particle angles/
/// speeds/lifetimes; defaults to `Random()` for real gameplay.
class ParticleSystem implements System {
  final Random random;

  ParticleSystem({Random? random}) : random = random ?? Random();

  @override
  String get name => 'particle';

  @override
  void update(World world, double dt) {
    _emit(world, dt);
    _age(world, dt);
  }

  void _emit(World world, double dt) {
    final emitters = world.storeOf<ParticleEmitter>();
    final positions = world.storeOf<Position>();

    for (var i = 0; i < emitters.length; i++) {
      final entity = emitters.entityAt(i);
      final emitter = emitters.denseAt(i);
      final origin = positions.get(entity);
      if (origin == null) continue;

      var toSpawn = emitter.burstCount;
      emitter.burstCount = 0;

      if (emitter.rate > 0) {
        emitter.accumulator += emitter.rate * dt;
        final whole = emitter.accumulator.floor();
        if (whole > 0) {
          toSpawn += whole;
          emitter.accumulator -= whole;
        }
      }

      for (var n = 0; n < toSpawn; n++) {
        _spawnParticle(world, emitter, origin);
      }
    }
  }

  void _spawnParticle(World world, ParticleEmitter emitter, Position origin) {
    final angle = _randomBetween(emitter.angleMin, emitter.angleMax);
    final speed = _randomBetween(emitter.speedMin, emitter.speedMax);
    final lifetime = _randomBetween(emitter.lifetimeMin, emitter.lifetimeMax);

    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(origin.x, origin.y));
    world.storeOf<Velocity>().set(id, Velocity(cos(angle) * speed, sin(angle) * speed));
    world.storeOf<Particle>().set(
          id,
          Particle(
            lifetime: lifetime,
            startScale: emitter.startScale,
            endScale: emitter.endScale,
            startAlpha: emitter.startAlpha,
            endAlpha: emitter.endAlpha,
            colorArgb: emitter.colorArgb,
            zIndex: emitter.zIndex,
          ),
        );
  }

  double _randomBetween(double min, double max) =>
      max <= min ? min : min + random.nextDouble() * (max - min);

  void _age(World world, double dt) {
    final particles = world.storeOf<Particle>();
    final expired = <EntityId>[];
    for (var i = 0; i < particles.length; i++) {
      final particle = particles.denseAt(i);
      particle.age += dt;
      if (particle.isExpired) expired.add(particles.entityAt(i));
    }
    // Destroyed after the scan (not inline) -- World.destroy triggers a
    // swap-remove in every component store, which would otherwise
    // shuffle indices out from under this loop mid-iteration.
    for (final id in expired) {
      world.destroy(id);
    }
  }
}
