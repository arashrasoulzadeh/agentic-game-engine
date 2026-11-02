import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// Mirrors docs/concepts/authoring.md: if you change a snippet there, change
/// it here (and vice versa) so the page cannot drift from the API.
class Rotation {
  double angle = 0;
}

class Health {
  double current;
  Health(this.current);
}

World _world() {
  final world = World(width: 800, height: 600);
  registerCoreComponents(world);
  world.components.register<Rotation>(
    'rotation',
    (r) => {'angle': r.angle},
    (j) => Rotation()..angle = (j['angle'] as num).toDouble(),
  );
  world.components.register<Health>(
    'health',
    (h) => {'current': h.current},
    (j) => Health((j['current'] as num).toDouble()),
  );
  return world;
}

class DamageSystem implements System {
  @override
  String get name => 'damage';
  @override
  void update(World world, double dt) {}
}

class DeathSystem implements System {
  @override
  String get name => 'death';
  @override
  void update(World world, double dt) {}
}

void main() {
  test('One call to start', () {
    final game = GameBuilder.create(width: 320, height: 240, fixedStep: 1 / 60);
    final ball = game.spawn([Position(10, 10), Velocity(60, 0)]);

    final steps = game.update(1 / 60);

    expect(steps, 1);
    expect(game.world.getComponent<Position>(ball)!.x, closeTo(11, 1e-6));
    game.pause();
    game.resume();
    game.stop();
  });

  test('Components', () {
    final world = _world();
    final id = world.spawn();
    world.setComponent(id, Position(1, 2));
    expect(world.getComponent<Position>(id)!.x, 1);
    expect(world.hasComponent<Position>(id), isTrue);
    expect(world.componentsOf<Position>().length, 1);
    world.removeComponent<Position>(id);
    expect(world.hasComponent<Position>(id), isFalse);
    world.destroy(id);
    expect(() => world.setComponent(id, Position(1, 2)), throwsStateError);
  });

  test('Creating entities', () {
    final world = _world();
    final a = world.spawnWith([Position(10, 20), Velocity(5, 0)]);
    final b = world.spawnAt(3, 4);
    final c = world.entity().at(10, 20).add(Collider(8)).build();

    world.addTag(a, 'enemy');
    expect(world.withTag('enemy').toList(), [a]);
    expect(world.getComponent<Position>(b)!.y, 4);
    expect(c.get<Collider>()!.radius, 8);
    expect(
      () => world.spawnWith([Position(0, 0), Rotation(), 'not a component']),
      throwsArgumentError,
    );
  });

  test('Finding things', () {
    final world = _world();
    world.spawnWith([Position(0, 0), Velocity(2, 0)]);
    world.spawnWith([Position(5, 5)]);
    expect(world.query<Position>().length, 2);
    const dt = 0.5;
    for (final (id, pos, vel) in world.query2<Position, Velocity>()) {
      pos.x += vel.x * dt;
      expect(id, isNonNegative);
    }
    expect(world.query2<Position, Velocity>().single.$2.x, 1);
  });

  test('Changing things while you loop', () {
    final world = _world();
    world.spawnWith([Health(0)]);
    world.spawnWith([Health(5)]);
    world.spawnWith([Health(-1)]);
    world.addSystemFn('reaper', (world, dt) {
      for (final (id, health) in world.query<Health>()) {
        if (health.current <= 0) world.commands.destroy(id);
      }
    });
    world.step(0.1);
    expect(world.query<Health>().length, 1);
  });

  test('Systems in a line', () {
    final world = _world();
    final id = world.spawnWith([Rotation()]);
    var hudRuns = 0;
    void updateHud(World world, double dt) => hudRuns++;

    world.addSystemFn('spin', (world, dt) {
      for (final (_, r) in world.query<Rotation>()) {
        r.angle += dt;
      }
    });
    world.addSystem(SystemGroup('combat', [DamageSystem(), DeathSystem()]));
    world.addSystemFn('hud', updateHud, phase: SystemPhase.late);
    world.setSystemEnabled('combat', false);

    expect(world.validateSystemOrder(), isEmpty);
    world.step(0.25);
    expect(world.getComponent<Rotation>(id)!.angle, 0.25);
    expect(hudRuns, 1);
    expect(world.isSystemEnabled('combat'), isFalse);
    expect(world.systemOrder, ['spin', 'combat', 'hud']);
  });

  test('Time and randomness', () {
    final world = World(width: 800, height: 600, seed: 42);
    var bosses = 0;
    var coins = 0;
    world.after(2.0, () => bosses++);
    final tick = world.every(0.5, () => coins++);
    for (var i = 0; i < 20; i++) {
      world.step(0.1);
    }
    expect(bosses, 1);
    expect(coins, 4);
    tick.cancel();
    expect(world.random.nextInt(6), inInclusiveRange(0, 5));
    expect(
      World(width: 1, height: 1, seed: 42).random.nextInt(1000),
      World(width: 1, height: 1, seed: 42).random.nextInt(1000),
    );
  });

  test('Saving, checking, inspecting', () {
    final world = _world();
    final id = world.spawnAt(1, 1);
    final data = world.save();
    world.setComponent(id, Position(9, 9));
    world.load(data);
    expect(world.getComponent<Position>(id)!.x, 1);

    final patch = {
      'entities': [
        {'id': 999},
      ],
    };
    expect(world.checkPatch(patch), hasLength(1));
    expect(
      () => world.applyPatch(patch, strict: true),
      throwsA(isA<WorldPatchException>()),
    );
    expect(world.debug(), contains('entities=1'));
  });

  test('CountdownTimer survives a save, as the page says', () {
    final world = _world()..addSystem(CountdownTimerSystem());
    world.spawnWith([CountdownTimer('boss', 1.0)]);
    var fired = 0;
    world.events.on<CountdownTimerFired>((_) => fired++);
    world.step(0.6);
    final copy = _world()..addSystem(CountdownTimerSystem());
    copy.load(world.save());
    copy.events.on<CountdownTimerFired>((_) => fired++);
    copy.step(0.5);
    expect(fired, 1);
  });
}
