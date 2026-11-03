import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world() {
  final w = World(width: 100, height: 100);
  registerCoreComponents(w);
  return w;
}

Map<String, dynamic> _level() => {
  'entities': [
    {
      'name': 'ok',
      'components': {
        'position': {'x': 1.0, 'y': 2.0},
      },
    },
    {
      'components': {
        'positon': {'x': 1.0, 'y': 2.0},
        'collider': {'radius': 'big'},
      },
    },
  ],
};

void main() {
  test('default loading still skips unknown component names', () {
    final w = _world();
    final named = Level.loadInto(w, _level().._fixCollider());
    expect(named.keys, ['ok']);
    expect(w.entities.count, 2);
  });

  test('strict lists every problem with its path and spawns nothing', () {
    final w = _world();
    expect(
      () => Level.loadInto(w, _level(), strict: true),
      throwsA(
        isA<LevelLoadException>().having(
          (e) => e.toString(),
          'message',
          allOf(
            contains('2 invalid component entries'),
            contains('entities[1].components.positon: unknown component'),
            contains('entities[1].components.collider'),
          ),
        ),
      ),
    );
    expect(w.entities.count, 0, reason: 'all-or-nothing');
  });

  test('strict accepts a clean level', () {
    final w = _world();
    final named = Level.loadInto(w, {
      'entities': [
        {
          'name': 'a',
          'components': {
            'position': {'x': 0.0, 'y': 0.0},
          },
        },
      ],
    }, strict: true);
    expect(named['a'], isNotNull);
  });
}

extension on Map<String, dynamic> {
  /// Makes the second entity's collider a valid object so only the typo'd
  /// name is left to be skipped.
  void _fixCollider() {
    final comps = (this['entities'] as List)[1]['components'] as Map;
    comps['collider'] = {'radius': 1.0};
  }
}
