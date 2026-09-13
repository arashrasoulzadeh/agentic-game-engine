import 'dart:math';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

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
}
