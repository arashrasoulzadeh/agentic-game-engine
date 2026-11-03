import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

class _Count implements System {
  final String id;
  int runs = 0;
  _Count(this.id);

  @override
  String get name => id;

  @override
  void update(World world, double dt) => runs++;
}

void main() {
  test('a disabled system is skipped but keeps its place', () {
    final world = World(width: 10, height: 10);
    final a = _Count('a');
    final b = _Count('b');
    world
      ..addSystem(a)
      ..addSystem(b);
    world.setSystemEnabled('a', false);
    world.step(0.1);
    expect([a.runs, b.runs], [0, 1]);
    expect(world.systemOrder, ['a', 'b']);
    expect(world.isSystemEnabled('a'), isFalse);
    expect(world.isSystemEnabled('b'), isTrue);
  });

  test('re-enabling resumes it', () {
    final world = World(width: 10, height: 10);
    final a = _Count('a');
    world.addSystem(a);
    world.setSystemEnabled('a', false);
    world.step(0.1);
    world.setSystemEnabled('a', true);
    world.step(0.1);
    expect(a.runs, 1);
  });

  test('an unknown name throws and lists the registered ones', () {
    final world = World(width: 10, height: 10)..addSystem(_Count('movement'));
    expect(
      () => world.setSystemEnabled('movment', false),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('"movment"'), contains('Registered: movement')),
        ),
      ),
    );
    expect(world.isSystemEnabled('movment'), isFalse);
  });

  test('every system sharing a name is toggled together', () {
    final world = World(width: 10, height: 10);
    final x = _Count('same');
    final y = _Count('same');
    world
      ..addSystem(x)
      ..addSystem(y);
    world.setSystemEnabled('same', false);
    world.step(0.1);
    expect([x.runs, y.runs], [0, 0]);
  });

  test('a disabled system is skipped under the profiler too', () {
    final world = World(width: 10, height: 10)..profiler = WorldProfiler();
    final a = _Count('a');
    world.addSystem(a);
    world.setSystemEnabled('a', false);
    world.step(0.1);
    expect(a.runs, 0);
  });
}
