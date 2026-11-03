import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world({BehaviorRegistry? behaviors, int seed = 0}) {
  final world = World(width: 200, height: 200, seed: seed);
  registerCoreComponents(world);
  SystemPresets.core(world, behaviors: behaviors);
  return world;
}

void main() {
  test('core preset registers its systems in this exact order', () {
    expect(_world().systemOrder, [
      'countdownTimer',
      'movement',
      'collision',
      'pushable',
      'tileAnimation',
      'tween',
      'particle',
    ]);
  });

  test('with behaviors, ai joins the pre-physics phase after the timer', () {
    expect(_world(behaviors: BehaviorRegistry()).systemOrder, [
      'countdownTimer',
      'ai',
      'movement',
      'collision',
      'pushable',
      'tileAnimation',
      'tween',
      'particle',
    ]);
  });

  test('the declared dependencies are satisfied', () {
    expect(_world().validateSystemOrder(), isEmpty);
  });

  test('moving the preset after the fact is caught by validation', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    world.addSystem(CollisionSystem(), after: ['movement']);
    world.addSystem(MovementSystem());
    expect(world.validateSystemOrder(), isNotEmpty);
  });

  test('it actually simulates: velocity moves an entity, collision events '
      'fire, a timer counts down', () {
    final world = _world();
    final mover = world.spawnWith([Position(0, 0), Velocity(10, 0)]);
    final other = world.spawnWith([Position(30, 0), Collider(5)]);
    world.setComponent(mover, Collider(5));
    var collisions = 0;
    world.events.on<CollisionEvent>((_) => collisions++);
    final timer = world.spawnWith([CountdownTimer('t', 0.5)]);
    var fired = 0;
    world.events.on<CountdownTimerFired>((_) => fired++);
    for (var i = 0; i < 40; i++) {
      world.step(0.1);
    }
    expect(world.getComponent<Position>(mover)!.x, greaterThan(0));
    expect(collisions, greaterThan(0));
    expect(fired, 1);
    expect(world.hasComponent<CountdownTimer>(timer), isFalse);
    expect(other, isNot(mover));
  });

  test('particles are reproducible per world seed and differ across seeds', () {
    String run(int seed) {
      final world = _world(seed: seed);
      world.spawnWith([
        Position(0, 0),
        ParticleEmitter(rate: 50, lifetimeMin: 1, lifetimeMax: 1),
      ]);
      for (var i = 0; i < 20; i++) {
        world.step(0.05);
      }
      return world.toJson()['entities'].toString();
    }

    expect(run(7), run(7));
    expect(run(7), isNot(run(8)));
  });
}
