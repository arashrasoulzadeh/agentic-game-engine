import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Run implements System {
  final String id;
  final List<String> log;
  final void Function(World world)? body;
  _Run(this.id, this.log, [this.body]);

  @override
  String get name => id;

  @override
  void update(World world, double dt) {
    log.add(id);
    body?.call(world);
  }
}

void main() {
  test('a group runs its children in order as one system', () {
    final log = <String>[];
    final world = World(width: 10, height: 10);
    world
      ..addSystem(_Run('before', log))
      ..addSystem(SystemGroup('combat', [_Run('a', log), _Run('b', log)]))
      ..addSystem(_Run('after', log));
    world.step(0.1);
    expect(log, ['before', 'a', 'b', 'after']);
    expect(world.systemOrder, ['before', 'combat', 'after']);
  });

  test('children are listed and the list is read-only', () {
    final log = <String>[];
    final group = SystemGroup('g', [_Run('a', log), _Run('b', log)]);
    expect(group.childNames, ['a', 'b']);
    expect(() => group.children.add(_Run('c', log)), throwsUnsupportedError);
  });

  test('commands queued by one child are applied before the next child', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final id = world.spawn();
    final seen = <bool>[];
    world.addSystem(
      SystemGroup('g', [
        _Run('kill', [], (w) => w.commands.destroy(id)),
        _Run('look', [], (w) => seen.add(w.entities.isAlive(id))),
      ]),
    );
    world.step(0.1);
    expect(seen, [false]);
  });

  test('disabling the group skips every child', () {
    final log = <String>[];
    final world = World(width: 10, height: 10)
      ..addSystem(SystemGroup('g', [_Run('a', log), _Run('b', log)]));
    world.setSystemEnabled('g', false);
    world.step(0.1);
    expect(log, isEmpty);
  });

  test('groups nest', () {
    final log = <String>[];
    final world = World(width: 10, height: 10)
      ..addSystem(
        SystemGroup('outer', [
          _Run('a', log),
          SystemGroup('inner', [_Run('b', log), _Run('c', log)]),
        ]),
      );
    world.step(0.1);
    expect(log, ['a', 'b', 'c']);
  });
}
