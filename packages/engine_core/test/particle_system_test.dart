import 'dart:math';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

import 'package:engine_core/src/rendering/particle_forces.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  return world;
}

int _countParticles(World world) => world.storeOf<Particle>().length;

void main() {
  test('Particle scale/alpha ramp linearly with progress, clamped past lifetime', () {
    final particle = Particle(
      lifetime: 2,
      startScale: 1,
      endScale: 0,
      startAlpha: 1,
      endAlpha: 0,
    );

    particle.age = 0;
    expect(particle.scale, 1);
    expect(particle.alpha, 1);

    particle.age = 1;
    expect(particle.scale, closeTo(0.5, 0.001));
    expect(particle.alpha, closeTo(0.5, 0.001));

    particle.age = 5; // past lifetime
    expect(particle.progress, 1);
    expect(particle.scale, 0);
    expect(particle.isExpired, isTrue);
  });

  test('Particle with followEmitter and emitterEntityId serializes correctly', () {
    final particle = Particle(
      lifetime: 2,
      startScale: 1,
      endScale: 0,
      startAlpha: 1,
      endAlpha: 0,
    );
    particle.followEmitter = true;
    particle.emitterEntityId = 42;

    final json = particle.toJson();
    expect(json['followEmitter'], true);
    expect(json['emitterEntityId'], 42);

    final decoded = Particle.fromJson(json);
    expect(decoded.followEmitter, true);
    expect(decoded.emitterEntityId, 42);
  });

  test('burstCount spawns that many particles in one tick and resets to 0', () {
    final world = _buildWorld();
    world.addSystem(ParticleSystem(random: Random(1)));

    final emitterEntity = world.spawn();
    world.storeOf<Position>().set(emitterEntity, Position(10, 10));
    final emitter = ParticleEmitter(burstCount: 5, lifetimeMin: 1, lifetimeMax: 1);
    world.storeOf<ParticleEmitter>().set(emitterEntity, emitter);

    world.step(0.016);

    expect(_countParticles(world), 5);
    expect(emitter.burstCount, 0);

    // No further particles without a new burst or rate.
    world.step(0.016);
    expect(_countParticles(world), 5);
  });

  test('continuous rate accumulates fractional particles across ticks', () {
    final world = _buildWorld();
    world.addSystem(ParticleSystem(random: Random(1)));

    final emitterEntity = world.spawn();
    world.storeOf<Position>().set(emitterEntity, Position(0, 0));
    world.storeOf<ParticleEmitter>().set(
          emitterEntity,
          ParticleEmitter(rate: 10, lifetimeMin: 10, lifetimeMax: 10),
        );

    // 10/sec * 0.05s = 0.5 particles/tick -- needs two ticks for the first one.
    world.step(0.05);
    expect(_countParticles(world), 0);
    world.step(0.05);
    expect(_countParticles(world), 1);
  });

  test('spawned particles get Position/Velocity and move via MovementSystem', () {
    final world = _buildWorld();
    world.addSystem(ParticleSystem(random: Random(1)));
    world.addSystem(MovementSystem());

    final emitterEntity = world.spawn();
    world.storeOf<Position>().set(emitterEntity, Position(50, 50));
    world.storeOf<ParticleEmitter>().set(
          emitterEntity,
          ParticleEmitter(
            burstCount: 1,
            speedMin: 100,
            speedMax: 100,
            lifetimeMin: 5,
            lifetimeMax: 5,
          ),
        );

    world.step(0.1);

    final particles = world.storeOf<Particle>();
    expect(particles.length, 1);
    final particleEntity = particles.entityAt(0);
    final pos = world.storeOf<Position>().get(particleEntity)!;
    final vel = world.storeOf<Velocity>().get(particleEntity)!;

    expect(vel.x * vel.x + vel.y * vel.y, closeTo(100 * 100, 0.01));
    // Moved from the emitter's spawn point by roughly velocity * dt.
    expect((pos.x - 50).abs() > 0 || (pos.y - 50).abs() > 0, isTrue);
  });

  test('particles are destroyed once their lifetime elapses', () {
    final world = _buildWorld();
    world.addSystem(ParticleSystem(random: Random(1)));

    final emitterEntity = world.spawn();
    world.storeOf<Position>().set(emitterEntity, Position(0, 0));
    world.storeOf<ParticleEmitter>().set(
          emitterEntity,
          ParticleEmitter(burstCount: 3, lifetimeMin: 0.2, lifetimeMax: 0.2),
        );

    world.step(0.01); // spawn
    expect(_countParticles(world), 3);

    world.step(0.3); // outlives the 0.2s lifetime
    expect(_countParticles(world), 0);
  });

  test('an emitter with no Position component is skipped, not a crash', () {
    final world = _buildWorld();
    world.addSystem(ParticleSystem(random: Random(1)));

    final emitterEntity = world.spawn();
    world.storeOf<ParticleEmitter>().set(emitterEntity, ParticleEmitter(burstCount: 3));

    expect(() => world.step(0.016), returnsNormally);
    expect(_countParticles(world), 0);
  });

  test('Particle and ParticleEmitter round-trip through toJson/fromJson', () {
    final particle = Particle(
      age: 0.4,
      lifetime: 2,
      startScale: 1,
      endScale: 0.2,
      startAlpha: 0.9,
      endAlpha: 0.1,
      colorArgb: 0xFF00FF00,
    );
    final decodedParticle = Particle.fromJson(particle.toJson());
    expect(decodedParticle.age, particle.age);
    expect(decodedParticle.lifetime, particle.lifetime);
    expect(decodedParticle.colorArgb, particle.colorArgb);

    final emitter = ParticleEmitter(rate: 3, burstCount: 2, accumulator: 0.7);
    final decodedEmitter = ParticleEmitter.fromJson(emitter.toJson());
    expect(decodedEmitter.rate, 3);
    expect(decodedEmitter.burstCount, 2);
    expect(decodedEmitter.accumulator, 0.7);
  });

  group('Emission shapes', () {
    test('circle emission spawns particles within radius', () {
      final world = _buildWorld();
      world.addSystem(ParticleSystem(random: Random(1)));

      final emitterEntity = world.spawn();
      world.storeOf<Position>().set(emitterEntity, Position(100, 100));
      world.storeOf<ParticleEmitter>().set(
            emitterEntity,
            ParticleEmitter(
              burstCount: 100,
              emissionShape: EmissionShape.circle,
              emissionRadius: 20,
              lifetimeMin: 5,
              lifetimeMax: 5,
            ),
          );

      world.step(0.01);

      final particles = world.storeOf<Particle>();
      final positions = world.storeOf<Position>();
      expect(particles.length, 100);

      for (var i = 0; i < particles.length; i++) {
        final pos = positions.get(particles.entityAt(i))!;
        final dx = pos.x - 100;
        final dy = pos.y - 100;
        final dist = sqrt(dx * dx + dy * dy);
        expect(dist, lessThanOrEqualTo(20 + 0.01), reason: 'particle should be within circle radius');
      }
    });

    test('rect emission spawns particles within bounds', () {
      final world = _buildWorld();
      world.addSystem(ParticleSystem(random: Random(1)));

      final emitterEntity = world.spawn();
      world.storeOf<Position>().set(emitterEntity, Position(100, 100));
      world.storeOf<ParticleEmitter>().set(
            emitterEntity,
            ParticleEmitter(
              burstCount: 100,
              emissionShape: EmissionShape.rect,
              emissionHalfWidth: 10,
              emissionHalfHeight: 5,
              lifetimeMin: 5,
              lifetimeMax: 5,
            ),
          );

      world.step(0.01);

      final particles = world.storeOf<Particle>();
      final positions = world.storeOf<Position>();
      expect(particles.length, 100);

      for (var i = 0; i < particles.length; i++) {
        final pos = positions.get(particles.entityAt(i))!;
        expect(pos.x, greaterThanOrEqualTo(90));
        expect(pos.x, lessThanOrEqualTo(110));
        expect(pos.y, greaterThanOrEqualTo(95));
        expect(pos.y, lessThanOrEqualTo(105));
      }
    });

    test('edge emission spawns particles along line segment', () {
      final world = _buildWorld();
      world.addSystem(ParticleSystem(random: Random(1)));

      final emitterEntity = world.spawn();
      world.storeOf<Position>().set(emitterEntity, Position(0, 0));
      world.storeOf<ParticleEmitter>().set(
            emitterEntity,
            ParticleEmitter(
              burstCount: 50,
              emissionShape: EmissionShape.edge,
              edgeStartX: -20,
              edgeStartY: 0,
              edgeEndX: 20,
              edgeEndY: 0,
              lifetimeMin: 5,
              lifetimeMax: 5,
            ),
          );

      world.step(0.01);

      final particles = world.storeOf<Particle>();
      final positions = world.storeOf<Position>();
      expect(particles.length, 50);

      for (var i = 0; i < particles.length; i++) {
        final pos = positions.get(particles.entityAt(i))!;
        expect(pos.x, greaterThanOrEqualTo(-20 - 0.01));
        expect(pos.x, lessThanOrEqualTo(20 + 0.01));
        expect(pos.y.abs(), lessThan(0.01)); // Should be on x-axis
      }
    });
  });

  group('Force fields', () {
    test('attractor pulls particles toward center', () {
      final world = _buildWorld();
      world.addSystem(ParticleSystem(random: Random(1)));
      world.addSystem(MovementSystem());

      // Particle at (100, 0), attractor at (0, 0) with strength 100
      final particleEntity = world.spawn();
      world.storeOf<Position>().set(particleEntity, Position(100, 0));
      world.storeOf<Velocity>().set(particleEntity, Velocity(0, 0));
      world.storeOf<Particle>().set(particleEntity, Particle(lifetime: 5));

      final attractorEntity = world.spawn();
      world.storeOf<Position>().set(attractorEntity, Position(0, 0));
      world.storeOf<ParticleForces>().set(
            attractorEntity,
            ParticleForces(radius: 200, strength: 1000),
          );

      world.addSystem(ParticleSystem(random: Random(1)));

      world.step(0.1);

      final pos = world.storeOf<Position>().get(particleEntity)!;
      final vel = world.storeOf<Velocity>().get(particleEntity)!;

      // Particle should have moved toward attractor (negative x direction)
      expect(vel.x, lessThan(0));
      expect(pos.x, lessThan(100));
    });

    test('repeller pushes particles away from center', () {
      final world = _buildWorld();
      world.addSystem(ParticleSystem(random: Random(1)));
      world.addSystem(MovementSystem());

      final particleEntity = world.spawn();
      world.storeOf<Position>().set(particleEntity, Position(50, 0));
      world.storeOf<Velocity>().set(particleEntity, Velocity(0, 0));
      world.storeOf<Particle>().set(particleEntity, Particle(lifetime: 5));

      final repellerEntity = world.spawn();
      world.storeOf<Position>().set(repellerEntity, Position(0, 0));
      world.storeOf<ParticleForces>().set(
            repellerEntity,
            ParticleForces(radius: 100, strength: -1000),
          );

      world.addSystem(ParticleSystem(random: Random(1)));

      world.step(0.1);

      final pos = world.storeOf<Position>().get(particleEntity)!;
      final vel = world.storeOf<Velocity>().get(particleEntity)!;

      // Particle should be pushed away (positive x direction)
      expect(vel.x, greaterThan(0));
      expect(pos.x, greaterThan(50));
    });

    test('wind applies constant directional force', () {
      final world = _buildWorld();
      world.addSystem(MovementSystem());

      final particleEntity = world.spawn();
      world.storeOf<Position>().set(particleEntity, Position(0, 0));
      world.storeOf<Velocity>().set(particleEntity, Velocity(0, 0));
      world.storeOf<Particle>().set(particleEntity, Particle(lifetime: 5));

      final windEntity = world.spawn();
      world.storeOf<Position>().set(windEntity, Position(0, 0)); // Wind entity needs position
      world.storeOf<ParticleForces>().set(
            windEntity,
            ParticleForces(
              isWind: true,
              strength: 500,
              windDirection: 0, // Rightward
            ),
          );

      world.addSystem(ParticleSystem(random: Random(1)));

      world.step(0.1);

      final vel = world.storeOf<Velocity>().get(particleEntity)!;

      // Should have positive x velocity from wind
      expect(vel.x, greaterThan(0));
      expect(vel.y.abs(), lessThan(1)); // No y component
    });
  });

  group('Follow emitter', () {
    test('particles follow emitter when followEmitter is true', () {
      final world = _buildWorld();
      world.addSystem(MovementSystem());

      final emitterEntity = world.spawn();
      world.storeOf<Position>().set(emitterEntity, Position(0, 0));
      world.storeOf<Velocity>().set(emitterEntity, Velocity(100, 0)); // Moving right
      world.storeOf<ParticleEmitter>().set(
            emitterEntity,
            ParticleEmitter(
              burstCount: 1,
              followEmitter: true,
              lifetimeMin: 10,
              lifetimeMax: 10,
              speedMin: 0,
              speedMax: 0,
            ),
          );

      world.addSystem(ParticleSystem(random: Random(1)));

      // Simulate 0.5 seconds in 0.1s steps
      for (var i = 0; i < 5; i++) {
        world.step(0.1);
      }

      final particles = world.storeOf<Particle>();
      final positions = world.storeOf<Position>();
      final particleEntity = particles.entityAt(0);
      final pos = positions.get(particleEntity)!;

      // Emitter is at x=50 (100 * 0.5), particle should be close
      expect(pos.x, greaterThan(40));
      expect(pos.x, lessThan(55));
    });
  });
}
