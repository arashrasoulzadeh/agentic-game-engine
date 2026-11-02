import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Noop implements System {
  final String id;
  _Noop(this.id);

  @override
  String get name => id;

  @override
  void update(World world, double dt) {}
}

void main() {
  test('a satisfied order has no problems', () {
    final world = World(width: 10, height: 10)
      ..addSystem(_Noop('movement'))
      ..addSystem(_Noop('collision'), after: ['movement']);
    expect(world.validateSystemOrder(), isEmpty);
  });

  test('a predecessor registered later is reported with both positions', () {
    final world = World(width: 10, height: 10)
      ..addSystem(_Noop('collision'), after: ['movement'])
      ..addSystem(_Noop('movement'));
    final problems = world.validateSystemOrder();
    expect(problems, hasLength(1));
    expect(
      problems.single,
      allOf(
        contains('"collision" (position 1)'),
        contains('"movement" runs later (position 2)'),
      ),
    );
  });

  test('a missing predecessor is reported with the registered names', () {
    final world = World(width: 10, height: 10)
      ..addSystem(_Noop('collision'), after: ['movment']);
    expect(
      world.validateSystemOrder().single,
      allOf(
        contains('no system named "movment"'),
        contains('Registered: collision'),
      ),
    );
  });

  test('phases count: a predecessor in a later phase violates the order', () {
    final world = World(width: 10, height: 10)
      ..addSystem(_Noop('damage'), phase: SystemPhase.postPhysics)
      ..addSystem(_Noop('hit'), after: ['damage']);
    expect(world.validateSystemOrder(), hasLength(1));
  });

  test('declaring after: does not reorder anything', () {
    final world = World(width: 10, height: 10)
      ..addSystem(_Noop('b'), after: ['a'])
      ..addSystem(_Noop('a'));
    expect(world.systemOrder, ['b', 'a']);
  });

  test('every declaration is checked and each problem listed', () {
    final world = World(width: 10, height: 10)
      ..addSystem(_Noop('x'), after: ['y', 'z'])
      ..addSystem(_Noop('y'));
    expect(world.validateSystemOrder(), hasLength(2));
  });

  test('a disabled predecessor still counts as registered', () {
    final world = World(width: 10, height: 10)
      ..addSystem(_Noop('a'))
      ..addSystem(_Noop('b'), after: ['a']);
    world.setSystemEnabled('a', false);
    expect(world.validateSystemOrder(), isEmpty);
  });
}
