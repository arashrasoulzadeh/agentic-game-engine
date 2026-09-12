import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('loadInto spawns one entity per item with its components applied', () {
    final world = _buildWorld();
    Level.loadInto(world, {
      'entities': [
        {
          'components': {
            'position': {'x': 10, 'y': 20},
            'collider': {'radius': 5},
          },
        },
        {
          'components': {
            'position': {'x': 30, 'y': 40},
          },
        },
      ],
    });

    expect(world.entities.count, 2);
    final positions = world.storeOf<Position>().length;
    expect(positions, 2);
  });

  test('entity with no components key spawns with no components', () {
    final world = _buildWorld();
    Level.loadInto(world, {
      'entities': [<String, dynamic>{}],
    });

    expect(world.entities.count, 1);
    expect(world.storeOf<Position>().length, 0);
  });

  test('throws LevelLoadException when "entities" key is missing', () {
    final world = _buildWorld();
    expect(
      () => Level.loadInto(world, {}),
      throwsA(isA<LevelLoadException>().having(
        (e) => e.message,
        'message',
        contains('entities'),
      )),
    );
  });

  test('throws LevelLoadException when "entities" is not a list', () {
    final world = _buildWorld();
    expect(
      () => Level.loadInto(world, {'entities': 'oops'}),
      throwsA(isA<LevelLoadException>()),
    );
  });

  test('throws LevelLoadException when an entity is not an object', () {
    final world = _buildWorld();
    expect(
      () => Level.loadInto(world, {
        'entities': [42],
      }),
      throwsA(isA<LevelLoadException>().having(
        (e) => e.message,
        'message',
        contains('entities[0]'),
      )),
    );
  });

  test('throws LevelLoadException when components is not an object', () {
    final world = _buildWorld();
    expect(
      () => Level.loadInto(world, {
        'entities': [
          {'components': 'oops'},
        ],
      }),
      throwsA(isA<LevelLoadException>()),
    );
  });

  test('throws LevelLoadException when a named component is not an object', () {
    final world = _buildWorld();
    expect(
      () => Level.loadInto(world, {
        'entities': [
          {
            'components': {'position': 'oops'},
          },
        ],
      }),
      throwsA(isA<LevelLoadException>().having(
        (e) => e.message,
        'message',
        contains('position'),
      )),
    );
  });
}
