import 'dart:math';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 200, height: 200);
  registerCoreComponents(world);
  world.addSystem(ParticleSystem(random: Random(1)));
  return world;
}

int _particles(World w) => w.componentsOf<Particle>().length;

void main() {
  test('explosion bursts once, in every direction', () {
    final world = _world();
    final e = world.spawnAt(100, 100);
    final emitter = ParticlePresets.explosion();
    world.setComponent(e, emitter);
    world.step(0.016);
    expect(_particles(world), 40);
    expect(emitter.burstCount, 0, reason: 'a burst fires only once');
    world.step(0.016);
    expect(_particles(world), 40);
    final velocities = world.componentsOf<Velocity>();
    final signs = {
      for (var i = 0; i < velocities.length; i++)
        (velocities.denseAt(i).x.sign, velocities.denseAt(i).y.sign),
    };
    expect(signs.length, greaterThan(2), reason: 'all around, not one way');
  });

  test('sparks and dust fly upward only (screen y is negative)', () {
    for (final preset in [ParticlePresets.sparks(), ParticlePresets.dust()]) {
      final world = _world();
      world.setComponent(world.spawnAt(0, 0), preset);
      world.step(0.016);
      final velocities = world.componentsOf<Velocity>();
      for (var i = 0; i < velocities.length; i++) {
        expect(velocities.denseAt(i).y, lessThanOrEqualTo(0));
      }
    }
  });

  test('smoke keeps emitting until its rate is set to 0', () {
    final world = _world();
    final emitter = ParticlePresets.smoke();
    world.setComponent(world.spawnAt(0, 0), emitter);
    for (var i = 0; i < 60; i++) {
      world.step(1 / 60);
    }
    expect(_particles(world), greaterThan(5));
    emitter.rate = 0;
    final before = _particles(world);
    world.step(1 / 60);
    expect(_particles(world), lessThanOrEqualTo(before));
  });

  test('colour is a parameter and each call is a fresh emitter', () {
    final a = ParticlePresets.explosion(colorArgb: 0xFF00FF00);
    final b = ParticlePresets.explosion();
    expect(a.colorArgb, 0xFF00FF00);
    expect(identical(a, b), isFalse);
    a.burstCount = 0;
    expect(b.burstCount, 40);
  });
}
