import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

Map<String, dynamic> _patch(List<Map<String, dynamic>> entities) => {
  'entities': entities,
};

void main() {
  test('a good patch has no problems', () {
    final world = _world();
    final id = world.spawnAt(0, 0);
    expect(
      world.checkPatch(
        _patch([
          {
            'id': id,
            'components': {
              'position': {'x': 5.0, 'y': 6.0},
            },
          },
        ]),
      ),
      isEmpty,
    );
  });

  test('checkPatch applies nothing', () {
    final world = _world();
    final id = world.spawnAt(0, 0);
    world.checkPatch(
      _patch([
        {
          'id': id,
          'components': {
            'position': {'x': 99.0, 'y': 99.0},
          },
        },
      ]),
    );
    expect(world.getComponent<Position>(id)!.x, 0);
  });

  test('every kind of problem is reported with its path', () {
    final world = _world();
    final id = world.spawnAt(0, 0);
    final problems = world.checkPatch({
      'entities': [
        7,
        {'id': 'nope'},
        {'id': 999},
        {'id': id, 'components': 'bad'},
        {
          'id': id,
          'components': {
            'warp': {'x': 1},
            'position': 'oops',
            'velocity': {'x': 'not a number', 'y': 0},
          },
        },
      ],
    });
    final byPath = {for (final p in problems) p.path: p.message};
    expect(byPath['entities[0]'], contains('must be an object'));
    expect(byPath['entities[1].id'], contains('must be an int'));
    expect(byPath['entities[2].id'], contains('entity 999 is not alive'));
    expect(byPath['entities[3].components'], contains('must be an object'));
    expect(
      byPath['entities[4].components.warp'],
      contains('unknown component'),
    );
    expect(byPath['entities[4].components.warp'], contains('position'));
    expect(
      byPath['entities[4].components.position'],
      contains('expected an object'),
    );
    expect(byPath.containsKey('entities[4].components.velocity'), isTrue);
    expect(problems, hasLength(7));
  });

  test('a missing or non-list entities key is a single problem', () {
    final world = _world();
    expect(world.checkPatch({}).single.path, 'entities');
    expect(world.checkPatch({'entities': 3}).single.message, contains('list'));
  });

  test('strict applyPatch throws with every problem and applies nothing', () {
    final world = _world();
    final id = world.spawnAt(1, 1);
    expect(
      () => world.applyPatch(
        _patch([
          {
            'id': id,
            'components': {
              'position': {'x': 50.0, 'y': 50.0},
            },
          },
          {'id': 999},
        ]),
        strict: true,
      ),
      throwsA(
        isA<WorldPatchException>().having(
          (e) => e.message,
          'message',
          allOf(contains('1 problem'), contains('entities[1].id')),
        ),
      ),
    );
    expect(world.getComponent<Position>(id)!.x, 1, reason: 'nothing applied');
  });

  test('lenient applyPatch still skips dead ids and unknown names', () {
    final world = _world();
    final id = world.spawnAt(1, 1);
    world.applyPatch(
      _patch([
        {'id': 999, 'components': {}},
        {
          'id': id,
          'components': {
            'warp': {},
            'position': {'x': 9.0, 'y': 9.0},
          },
        },
      ]),
    );
    expect(world.getComponent<Position>(id)!.x, 9);
  });

  test('a strict patch that is fine applies', () {
    final world = _world();
    final id = world.spawnAt(1, 1);
    world.applyPatch(
      _patch([
        {
          'id': id,
          'components': {
            'position': {'x': 4.0, 'y': 4.0},
          },
        },
      ]),
      strict: true,
    );
    expect(world.getComponent<Position>(id)!.x, 4);
  });

  test('checkComponent explains unknown names, shapes and bad fields', () {
    final world = _world();
    expect(
      world.components.checkComponent('position', {'x': 1, 'y': 2}),
      isNull,
    );
    expect(
      world.components.checkComponent('nope', {}),
      contains('unknown component "nope"'),
    );
    expect(
      world.components.checkComponent('position', 3),
      'expected an object, got int',
    );
    expect(world.components.checkComponent('position', {}), isNotNull);
  });
}
