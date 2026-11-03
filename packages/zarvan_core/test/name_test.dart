import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 10, height: 10);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('find returns the entity with that name, and null otherwise', () {
    final world = _world();
    final a = world.spawn();
    final b = world.spawn();
    world.setName(a, 'player');
    world.setName(b, 'exit');
    expect(world.find('exit'), b);
    expect(world.find('player'), a);
    expect(world.find('nobody'), isNull);
    expect(world.nameOf(a), 'player');
    expect(world.nameOf(world.spawn()), isNull);
  });

  test('renaming replaces the old name', () {
    final world = _world();
    final a = world.spawn();
    world.setName(a, 'old');
    world.setName(a, 'new');
    expect(world.find('old'), isNull);
    expect(world.find('new'), a);
  });

  test('a duplicate name resolves to the lowest id, and destroy frees it', () {
    final world = _world();
    final a = world.spawn();
    final b = world.spawn();
    world.setName(b, 'twin');
    world.setName(a, 'twin');
    expect(world.find('twin'), a);
    world.destroy(a);
    expect(world.find('twin'), b);
  });

  test('level entities with a name key are findable by name', () {
    final world = _world();
    final named = Level.loadInto(world, {
      'entities': [
        {
          'name': 'hero',
          'components': {
            'position': {'x': 1.0, 'y': 2.0},
          },
        },
        {
          'components': {
            'position': {'x': 3.0, 'y': 4.0},
          },
        },
      ],
    });
    expect(world.find('hero'), named['hero']);
    expect(world.toJson().toString(), contains('hero'));
  });

  test('loading a named level works when Name is not registered', () {
    final world = World(width: 10, height: 10);
    world.components.register<Position>(
      'position',
      (p) => p.toJson(),
      Position.fromJson,
    );
    final named = Level.loadInto(world, {
      'entities': [
        {
          'name': 'solo',
          'components': {
            'position': {'x': 1.0, 'y': 2.0},
          },
        },
      ],
    });
    expect(named['solo'], isNotNull);
  });

  test('Name JSON round-trips', () {
    expect(Name.fromJson(const Name('x').toJson()).value, 'x');
  });
}
