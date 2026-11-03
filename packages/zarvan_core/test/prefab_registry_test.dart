import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

PrefabRegistry _registry() => PrefabRegistry()
  ..register(
    Prefab(
      name: 'torch',
      entities: [
        LevelEntity(
          name: 'torch',
          components: {
            'position': {'x': 0.0, 'y': 0.0},
          },
        ),
        LevelEntity(
          components: {
            'position': {'x': 4.0, 'y': 0.0},
            'collider': {'radius': 2.0},
          },
        ),
      ],
    ),
  );

World _world() {
  final w = World(width: 100, height: 100);
  registerCoreComponents(w);
  return w;
}

void main() {
  test('spawn places fresh entities at the origin, root first', () {
    final w = _world();
    final r = _registry();
    final a = r.spawn(w, 'torch', 10, 20);
    final b = r.spawn(w, 'torch', 50, 20);
    expect(a.ids, hasLength(2));
    expect(w.getComponent<Position>(a.root)!.x, 10);
    expect(w.getComponent<Position>(a.ids[1])!.x, 14);
    expect(w.getComponent<Collider>(a.ids[1])!.radius, 2);
    expect(w.getComponent<Position>(b.root)!.x, 50);
    expect(w.entities.count, 4, reason: 'independent copies');
  });

  test('names are made unique against takenNames', () {
    final w = _world();
    final r = _registry();
    expect(r.spawn(w, 'torch', 0, 0).named.keys, ['torch']);
    final second = r.spawn(w, 'torch', 0, 0, takenNames: {'torch'});
    expect(second.named.keys, ['torch2']);
  });

  test('unknown names list the known ones; bad components fail loudly', () {
    final w = _world();
    final r = _registry();
    expect(
      () => r.spawn(w, 'trch', 0, 0),
      throwsA(
        isA<ArgumentError>().having((e) => '$e', 'msg', contains('torch')),
      ),
    );
    r.registerJson({
      'name': 'bad',
      'entities': [
        {
          'components': {
            'position': {'x': 1.0, 'y': 1.0},
            'positon': {'x': 1.0, 'y': 1.0},
          },
        },
      ],
    });
    final before = w.entities.count;
    expect(
      () => r.spawn(w, 'bad', 0, 0),
      throwsA(
        isA<ArgumentError>().having((e) => '$e', 'msg', contains('positon')),
      ),
    );
    expect(w.entities.count, before, reason: 'nothing spawned');
    expect(r.has('bad'), isTrue);
    expect(r.names, ['bad', 'torch']);
  });

  test('a prefab round-trips through JSON into the registry', () {
    final w = _world();
    final r = PrefabRegistry()..registerJson(_registry().spawnJsonForTest());
    expect(w.getComponent<Position>(r.spawn(w, 'torch', 5, 5).root)!.x, 5);
  });
}

extension on PrefabRegistry {
  Map<String, dynamic> spawnJsonForTest() => Prefab(
    name: 'torch',
    entities: [
      LevelEntity(
        components: {
          'position': {'x': 0.0, 'y': 0.0},
        },
      ),
    ],
  ).toJson();
}
