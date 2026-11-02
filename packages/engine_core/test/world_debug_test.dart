import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('an empty world says so', () {
    final world = World(width: 320, height: 240, seed: 4);
    expect(
      world.debug(),
      'World 320x240 tick=0 seed=4 entities=0\n'
      'components: (none)\n'
      'systems: (none)',
    );
  });

  test('counts, system order and disabled systems are listed', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    SystemPresets.core(world);
    world.spawnWith([Position(0, 0), Velocity(1, 1)]);
    world.spawnWith([Position(5, 5)]);
    world.setSystemEnabled('tween', false);
    world.step(0.1);
    final text = world.debug();
    expect(text, contains('tick=1'));
    expect(text, contains('entities=2'));
    expect(text, contains('components: position=2, velocity=1'));
    expect(text, contains('movement -> collision'));
    expect(text, contains('tween (disabled)'));
    expect(text, isNot(contains('order problem')));
  });

  test('order problems and queued commands are surfaced', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    world.addSystemFn('b', (_, _) {}, after: ['a']);
    world.addSystemFn('a', (_, _) {});
    final id = world.spawnAt(0, 0);
    world.commands.destroy(id);
    final text = world.debug();
    expect(
      text,
      contains('order problem: "b" (position 1) must run after "a"'),
    );
    expect(text, contains('queued commands: 1'));
  });
}
