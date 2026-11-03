import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

class _Sys implements System {
  @override
  String get name => 'mover';
  @override
  void update(World world, double dt) {}
}

void main() {
  test('describe reports counts, schema fields, systems and warnings', () {
    final world = World(width: 50, height: 40, seed: 3);
    registerCoreComponents(world);
    world.addSystem(_Sys());
    world.setSystemEnabled('mover', false);
    world.spawnWith([Position(1, 2), Velocity(0, 0)]);
    world.spawn();
    world.step(0.5);

    final d = world.describe();
    expect(d['seed'], 3);
    expect(d['width'], 50);
    expect(d['entities'], 2);
    expect(d['tick'], 1);
    final components = d['components'] as Map;
    expect(components.keys, containsAll(['position', 'velocity']));
    expect((components['position'] as Map)['count'], 1);
    final fields = (components['position'] as Map)['fields'] as List;
    expect(fields.first, {'name': 'x', 'type': 'double', 'required': true});
    expect(d['systems'], [
      {'name': 'mover', 'enabled': false},
    ]);
    expect(d['orderProblems'], isEmpty);
  });

  test('a component without a schema has a count but no fields', () {
    final world = World(width: 1, height: 1);
    world.components.register<int>(
      'thing',
      (v) => {'v': v},
      (j) => j['v'] as int,
    );
    world.setComponent(world.spawn(), 7);
    final thing = (world.describe()['components'] as Map)['thing'] as Map;
    expect(thing, {'count': 1});
  });

  test('warnings appear and the result is JSON-encodable', () {
    final world = World(width: 1, height: 1);
    world.warnings.warn('careful');
    final d = world.describe();
    expect(d['warnings'], ['careful']);
    expect(() => d.toString(), returnsNormally);
  });
}
