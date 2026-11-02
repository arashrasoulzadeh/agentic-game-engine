import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('a function system runs each step with the world and dt', () {
    final world = World(width: 10, height: 10);
    final seen = <double>[];
    world.addSystemFn('probe', (w, dt) {
      expect(w, same(world));
      seen.add(dt);
    });
    world.step(0.25);
    world.step(0.5);
    expect(seen, [0.25, 0.5]);
    expect(world.systemOrder, ['probe']);
  });

  test('it takes a phase and after like any system', () {
    final world = World(width: 10, height: 10)
      ..addSystemFn('main', (_, _) {})
      ..addSystemFn('first', (_, _) {}, phase: SystemPhase.prePhysics)
      ..addSystemFn('needs', (_, _) {}, after: ['ghost']);
    expect(world.systemOrder, ['first', 'main', 'needs']);
    expect(world.validateSystemOrder(), hasLength(1));
  });

  test('it can be toggled by name and returns the system', () {
    final world = World(width: 10, height: 10);
    var runs = 0;
    final system = world.addSystemFn('count', (_, _) => runs++);
    expect(system.name, 'count');
    world.setSystemEnabled('count', false);
    world.step(0.1);
    expect(runs, 0);
  });

  test('it composes with queries and commands', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final id = world.spawnAt(0, 0);
    world.addSystemFn('reaper', (w, dt) {
      for (final (e, _) in w.query<Position>()) {
        w.commands.destroy(e);
      }
    });
    world.step(0.1);
    expect(world.entities.isAlive(id), isFalse);
  });
}
