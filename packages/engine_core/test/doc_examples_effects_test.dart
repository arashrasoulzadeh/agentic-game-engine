// The samples in docs/concepts/effects.md, executed so the guide cannot drift.
import 'dart:math';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  late World world;

  setUp(() {
    world = World(width: 500, height: 500);
    registerCoreComponents(world);
  });

  test('a tween eases a number over time and announces when it finishes', () {
    world.addSystem(TweenSystem());
    final fade = world.spawn();
    world.storeOf<Tween>().set(
          fade,
          Tween(from: 1, to: 0, duration: 2, easing: EasingType.easeOutQuad),
        );
    final done = <EntityId>[];
    world.events.on<TweenCompleteEvent>((e) => done.add(e.entity));

    for (var i = 0; i < 60; i++) {
      world.step(1 / 60);
    }
    final halfway = world.storeOf<Tween>().get(fade)!.value;
    expect(halfway, inInclusiveRange(0.2, 0.3), reason: 'easeOut: already past half way down');
    expect(done, isEmpty);

    for (var i = 0; i < 61; i++) {
      world.step(1 / 60);
    }
    expect(world.storeOf<Tween>().get(fade)!.value, 0);
    expect(done, [fade], reason: 'fires exactly once');
  });

  test('pingPong tweens bounce forever and never complete', () {
    world.addSystem(TweenSystem());
    final e = world.spawn();
    world.storeOf<Tween>().set(e, Tween(from: 0, to: 10, duration: 1, pingPong: true));
    for (var i = 0; i < 90; i++) {
      world.step(1 / 60);
    }
    final t = world.storeOf<Tween>().get(e)!;
    expect(t.isComplete, isFalse);
    expect(t.value, lessThan(10), reason: 'on the way back');
  });

  test('a burst emitter spawns particles that age out and are removed', () {
    world.addSystem(ParticleSystem(random: Random(1)));
    final fire = world.spawn();
    world.storeOf<Position>().set(fire, Position(100, 100));
    world.storeOf<ParticleEmitter>().set(
          fire,
          ParticleEmitter(burstCount: 20, lifetimeMin: 0.5, lifetimeMax: 0.5),
        );

    world.step(1 / 60);
    expect(world.storeOf<Particle>().length, 20);
    expect(world.storeOf<ParticleEmitter>().get(fire)!.burstCount, 0, reason: 'a burst fires once');

    for (var i = 0; i < 40; i++) {
      world.step(1 / 60);
    }
    expect(world.storeOf<Particle>().length, 0);
  });

  test('a steady emitter spawns at its rate', () {
    world.addSystem(ParticleSystem(random: Random(1)));
    final smoke = world.spawn();
    world.storeOf<Position>().set(smoke, Position(0, 0));
    world.storeOf<ParticleEmitter>().set(
          smoke,
          ParticleEmitter(rate: 30, lifetimeMin: 10, lifetimeMax: 10),
        );
    for (var i = 0; i < 60; i++) {
      world.step(1 / 60);
    }
    expect(world.storeOf<Particle>().length, inInclusiveRange(29, 31));
  });
}
