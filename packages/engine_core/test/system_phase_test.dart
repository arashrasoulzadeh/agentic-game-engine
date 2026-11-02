import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Run implements System {
  final String id;
  final List<String> log;
  _Run(this.id, this.log);

  @override
  String get name => id;

  @override
  void update(World world, double dt) => log.add(id);
}

void main() {
  test('systems without a phase keep their insertion order', () {
    final log = <String>[];
    final world = World(width: 10, height: 10)
      ..addSystem(_Run('a', log))
      ..addSystem(_Run('b', log))
      ..addSystem(_Run('c', log));
    world.step(0.1);
    expect(log, ['a', 'b', 'c']);
    expect(world.systemOrder, ['a', 'b', 'c']);
  });

  test('phases run in order regardless of when they were added', () {
    final log = <String>[];
    final world = World(width: 10, height: 10)
      ..addSystem(_Run('late', log), phase: SystemPhase.late)
      ..addSystem(_Run('post', log), phase: SystemPhase.postPhysics)
      ..addSystem(_Run('main', log))
      ..addSystem(_Run('pre', log), phase: SystemPhase.prePhysics);
    world.step(0.1);
    expect(log, ['pre', 'main', 'post', 'late']);
    expect(world.systemOrder, ['pre', 'main', 'post', 'late']);
  });

  test('inside a phase, insertion order holds (stable)', () {
    final log = <String>[];
    final world = World(width: 10, height: 10)
      ..addSystem(_Run('p1', log), phase: SystemPhase.prePhysics)
      ..addSystem(_Run('m1', log))
      ..addSystem(_Run('p2', log), phase: SystemPhase.prePhysics)
      ..addSystem(_Run('m2', log))
      ..addSystem(_Run('l1', log), phase: SystemPhase.late)
      ..addSystem(_Run('m3', log))
      ..addSystem(_Run('l2', log), phase: SystemPhase.late);
    expect(world.systemOrder, ['p1', 'p2', 'm1', 'm2', 'm3', 'l1', 'l2']);
  });

  test('enabling and disabling does not change phase order', () {
    final log = <String>[];
    final world = World(width: 10, height: 10)
      ..addSystem(_Run('main', log))
      ..addSystem(_Run('pre', log), phase: SystemPhase.prePhysics);
    world.setSystemEnabled('pre', false);
    world.step(0.1);
    world.setSystemEnabled('pre', true);
    world.step(0.1);
    expect(log, ['main', 'pre', 'main']);
  });
}
