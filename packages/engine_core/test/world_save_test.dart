import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _world({int seed = 3}) {
  final world = World(width: 100, height: 100, seed: seed);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('a save is plain JSON that survives encode/decode', () {
    final world = _world();
    world.spawnWith([Position(1, 2), Velocity(3, 4)]);
    final save = world.save();
    final copy = (jsonDecode(jsonEncode(save)) as Map).cast<String, dynamic>();
    expect(copy['version'], 1);
    expect(copy['seed'], 3);
  });

  test('load into a fresh world restores ids, components and tick', () {
    final world = _world();
    final a = world.spawnWith([Position(1, 2)]);
    final b = world.spawnWith([Position(5, 6)]);
    world.destroy(a);
    world.step(0.1);
    world.step(0.1);

    final other = _world();
    other.load(world.save());
    expect(other.tick, 2);
    expect(other.entities.all.toSet(), {b});
    expect(other.getComponent<Position>(b)!.x, 5);
  });

  test('the random stream resumes exactly where the save was taken', () {
    final world = _world();
    for (var i = 0; i < 7; i++) {
      world.random.nextDouble();
    }
    final save = world.save();
    final expected = [for (var i = 0; i < 5; i++) world.random.nextInt(1000)];

    final other = _world(seed: 999);
    other.load(save);
    expect([for (var i = 0; i < 5; i++) other.random.nextInt(1000)], expected);
  });

  test('load replaces what was there: extra entities are destroyed and '
      'changed ones rewound', () {
    final world = _world();
    final keep = world.spawnWith([Position(1, 1)]);
    final save = world.save();
    world.setComponent(keep, Position(9, 9));
    final extra = world.spawnWith([Position(2, 2)]);
    world.load(save);
    expect(world.entities.isAlive(extra), isFalse);
    expect(world.getComponent<Position>(keep)!.x, 1);
  });

  test('countdown timers survive a save and keep counting', () {
    final world = _world()..addSystem(CountdownTimerSystem());
    world.spawnWith([CountdownTimer('t', 1.0)]);
    world.step(0.4);
    final other = _world()..addSystem(CountdownTimerSystem());
    other.load(world.save());
    var fired = 0;
    other.events.on<CountdownTimerFired>((_) => fired++);
    other.step(0.5);
    expect(fired, 0);
    other.step(0.2);
    expect(fired, 1);
  });

  test(
    'data without a version 1 marker is rejected before changing anything',
    () {
      final world = _world();
      final id = world.spawnWith([Position(1, 1)]);
      expect(
        () => world.load({'tick': 0, 'entities': {}}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no version'),
          ),
        ),
      );
      expect(() => world.load({'version': 2}), throwsFormatException);
      expect(world.entities.isAlive(id), isTrue);
    },
  );

  test('closure timers are not part of a save (documented)', () {
    final world = _world();
    var fired = 0;
    world.after(0.1, () => fired++);
    final other = _world();
    other.load(world.save());
    other.step(0.2);
    expect(fired, 0);
  });
}
