import 'dart:math';

import 'particle.dart';
import 'particle_emitter.dart';
import 'particle_forces.dart';
import '../physics/position.dart';
import '../physics/velocity.dart';
import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';

/// Spawns particles from every `ParticleEmitter` (continuous [rate] and
/// one-shot `burstCount`), then ages and destroys every `Particle`
/// whose lifetime has elapsed. Relies on `MovementSystem` (also
/// registered by you, same as any other system) to actually move
/// spawned particles by the `Velocity` this system gives them —
/// deliberately not duplicated here.
///
/// Handles:
/// - Multiple emission shapes (point, circle, rect, edge)
/// - Force fields (attractors/repellers, wind)
/// - Particles that follow their emitter entity
/// - TileMap collision (via engine_platformer's extension)
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
    _applyForces(world, dt);
    _followEmitters(world, dt);
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
        _spawnParticle(world, emitter, origin, entity);
      }
    }
  }

  void _spawnParticle(World world, ParticleEmitter emitter, Position origin, EntityId emitterEntityId) {
    double spawnX = origin.x;
    double spawnY = origin.y;

    switch (emitter.emissionShape) {
      case EmissionShape.circle:
        if (emitter.emissionRadius > 0) {
          final angle = _randomBetween(0, 2 * pi);
          final radius = _randomBetween(0, emitter.emissionRadius);
          spawnX += cos(angle) * radius;
          spawnY += sin(angle) * radius;
        }
        break;
      case EmissionShape.rect:
        if (emitter.emissionHalfWidth > 0 || emitter.emissionHalfHeight > 0) {
          spawnX += _randomBetween(-emitter.emissionHalfWidth, emitter.emissionHalfWidth);
          spawnY += _randomBetween(-emitter.emissionHalfHeight, emitter.emissionHalfHeight);
        }
        break;
      case EmissionShape.edge:
        final t = _randomBetween(0, 1);
        spawnX += emitter.edgeStartX + (emitter.edgeEndX - emitter.edgeStartX) * t;
        spawnY += emitter.edgeStartY + (emitter.edgeEndY - emitter.edgeStartY) * t;
        break;
      case EmissionShape.point:
        break;
    }

    final angle = _randomBetween(emitter.angleMin, emitter.angleMax);
    final speed = _randomBetween(emitter.speedMin, emitter.speedMax);
    final lifetime = _randomBetween(emitter.lifetimeMin, emitter.lifetimeMax);

    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(spawnX, spawnY));
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
          )..followEmitter = emitter.followEmitter
           ..emitterEntityId = emitter.followEmitter ? emitterEntityId : null,
        );
  }

  void _applyForces(World world, double dt) {
    final forces = world.storeOf<ParticleForces>();
    if (forces.length == 0) return;

    final particles = world.storeOf<Particle>();
    final positions = world.storeOf<Position>();
    final velocities = world.storeOf<Velocity>();

    for (var i = 0; i < particles.length; i++) {
      final particle = particles.denseAt(i);
      final entity = particles.entityAt(i);
      final pos = positions.get(entity);
      final vel = velocities.get(entity);
      if (pos == null || vel == null) continue;

      for (var j = 0; j < forces.length; j++) {
        final force = forces.denseAt(j);
        final forcePos = positions.get(forces.entityAt(j));
        if (forcePos == null) continue;

        if (force.isWind) {
          vel.x += cos(force.windDirection) * force.strength * dt;
          vel.y += sin(force.windDirection) * force.strength * dt;
        } else {
          final dx = forcePos.x - pos.x;
          final dy = forcePos.y - pos.y;
          final distSq = dx * dx + dy * dy;
          final radiusSq = force.radius * force.radius;

          if (distSq > radiusSq) continue;

          final dist = sqrt(distSq);
          if (dist == 0) continue;

          final falloff = 1.0 - pow(dist / force.radius, force.falloffExponent);
          final fx = (dx / dist) * force.strength * falloff * dt;
          final fy = (dy / dist) * force.strength * falloff * dt;

          vel.x += fx;
          vel.y += fy;
        }
      }
    }
  }

  void _followEmitters(World world, double dt) {
    final particles = world.storeOf<Particle>();
    final positions = world.storeOf<Position>();
    final velocities = world.storeOf<Velocity>();

    for (var i = 0; i < particles.length; i++) {
      final particle = particles.denseAt(i);
      if (!particle.followEmitter || particle.emitterEntityId == null) continue;

      final emitterPos = positions.get(particle.emitterEntityId!);
      if (emitterPos == null) continue;

      final entity = particles.entityAt(i);
      final particlePos = positions.get(entity);
      final velocity = velocities.get(entity);
      if (particlePos == null || velocity == null) continue;

      final dx = emitterPos.x - particlePos.x;
      final dy = emitterPos.y - particlePos.y;
      final distSq = dx * dx + dy * dy;

      if (distSq < 0.01) continue;

      const followStrength = 50.0;
      velocity.x += dx * followStrength * dt;
      velocity.y += dy * followStrength * dt;
    }
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
    for (final id in expired) {
      world.destroy(id);
    }
  }
}
