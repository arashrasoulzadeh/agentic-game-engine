import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Run implements System {
  final String id;
  final void Function(World world) body;
  _Run(this.id, this.body);

  @override
  String get name => id;

  @override
  void update(World world, double dt) => body(world);
}

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('nothing changes until apply', () {
    final world = _world();
    final id = world.spawn();
    world.setComponent(id, Position(0, 0));
    world.commands
      ..destroy(id)
      ..set(id, Velocity(1, 1));
    expect(world.commands.length, 2);
    expect(world.entities.isAlive(id), isTrue);
    expect(world.hasComponent<Velocity>(id), isFalse);
    world.commands.apply();
    expect(world.commands.isEmpty, isTrue);
    expect(world.entities.isAlive(id), isFalse);
  });

  test('destroying every entity from inside a forward loop no longer skips '
      'any (the golden test shows the immediate version does)', () {
    final world = _world();
    final ids = [for (var i = 0; i < 4; i++) world.spawn()];
    for (final id in ids) {
      world.setComponent(id, Position(0, 0));
    }
    final store = world.componentsOf<Position>();
    final visited = <EntityId>[];
    for (var i = 0; i < store.length; i++) {
      final id = store.entityAt(i);
      visited.add(id);
      world.commands.destroy(id);
    }
    world.commands.apply();
    expect(visited, ids);
    expect(world.entities.count, 0);
  });

  test('commands run in the order queued', () {
    final world = _world();
    final id = world.spawn();
    world.commands
      ..set(id, Position(1, 1))
      ..set(id, Position(2, 2))
      ..remove<Position>(id)
      ..set(id, Position(3, 3));
    world.commands.apply();
    expect(world.getComponent<Position>(id)!.x, 3);
  });

  test('spawn is immediate and the id can be used by later commands', () {
    final world = _world();
    final id = world.commands.spawn();
    expect(world.entities.isAlive(id), isTrue);
    world.commands.set(id, Position(4, 5));
    world.commands.apply();
    expect(world.getComponent<Position>(id)!.y, 5);
  });

  test('commands for an entity destroyed earlier in the queue are skipped', () {
    final world = _world();
    final id = world.spawn();
    world.commands
      ..destroy(id)
      ..set(id, Position(0, 0))
      ..destroy(id);
    world.commands.apply();
    expect(world.entities.count, 0);
    expect(world.componentsOf<Position>().length, 0);
  });

  test('a command queued for a dead entity does not land on the entity that '
      'reuses its id', () {
    final world = _world();
    final old = world.spawn();
    world.commands.set(old, Position(9, 9));
    world.destroy(old);
    final reused = world.spawn();
    expect(reused, old);
    world.commands.apply();
    expect(world.hasComponent<Position>(reused), isFalse);
  });

  test('step applies commands after each system, so the next system sees '
      'them, and the queue is empty afterwards', () {
    final world = _world();
    final id = world.spawn();
    world.setComponent(id, Position(0, 0));
    final seen = <bool>[];
    world
      ..addSystem(_Run('kill', (w) => w.commands.destroy(id)))
      ..addSystem(_Run('look', (w) => seen.add(w.entities.isAlive(id))));
    world.step(0.1);
    expect(seen, [false]);
    expect(world.commands.isEmpty, isTrue);
  });

  test(
    'commands queued by event handlers are applied at the end of the step',
    () {
      final world = _world();
      final id = world.spawn();
      world.events.on<String>((_) => world.commands.destroy(id));
      world.events.emit('go');
      world.step(0.1);
      expect(world.entities.isAlive(id), isFalse);
    },
  );

  test('step applies commands with the profiler enabled too', () {
    final world = _world()..profiler = WorldProfiler();
    final id = world.spawn();
    world.addSystem(_Run('kill', (w) => w.commands.destroy(id)));
    world.step(0.1);
    expect(world.entities.isAlive(id), isFalse);
  });

  test('a failing command does not strand the rest; the first error is '
      'rethrown after they ran', () {
    final world = _world();
    final id = world.spawn();
    world.commands
      ..set(id, 'not a registered component type')
      ..set(id, Position(1, 1));
    expect(world.commands.apply, throwsStateError);
    expect(world.getComponent<Position>(id)!.x, 1);
    expect(world.commands.isEmpty, isTrue);
  });
}
