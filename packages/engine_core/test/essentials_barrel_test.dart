// Imports only the essentials barrel: if a daily-use type were missing from it,
// this would stop compiling.
import 'package:engine_core/engine_core_essentials.dart';
import 'package:test/test.dart';

void main() {
  test('the essentials barrel is enough to build, load and query a world', () {
    final game = GameBuilder.create(width: 100, height: 100);
    final world = game.world;
    final hero = world.spawnWith([Position(1, 2), Velocity(3, 0), Collider(4)]);
    world.setName(hero, 'hero');
    world.addTag(hero, 'friend');
    final named = Level.loadInto(world, {
      'entities': [
        {
          'name': 'coin',
          'components': {
            'position': {'x': 5.0, 'y': 5.0},
          },
        },
      ],
    });
    expect(world.find('hero'), hero);
    expect(world.withTag('friend'), [hero]);
    expect(named['coin'], isNotNull);
    expect(world.query<Position>().length, 2);
    world.commands.destroy(named['coin']!);
    game.update(1 / 60);
    expect(world.find('coin'), isNull);
    expect(WorldView(world).component<Position>(hero)!.x, closeTo(1, 5));
    final registry = PrefabRegistry();
    expect(registry.has('x'), isFalse);
    expect(BehaviorRegistry().has('x'), isFalse);
  });
}
