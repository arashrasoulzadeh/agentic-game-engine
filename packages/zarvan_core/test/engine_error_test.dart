import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 10, height: 10);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('a strict patch failure carries every located problem', () {
    final world = _world();
    final id = world.spawn();
    try {
      world.applyPatch({
        'entities': [
          {
            'id': id,
            'components': {
              'positon': {'x': 1, 'y': 2},
            },
          },
        ],
      }, strict: true);
      fail('expected a WorldPatchException');
    } on WorldPatchException catch (e) {
      expect(e, isA<EngineError>());
      expect(e.code, 'patch_invalid');
      final json = e.toJson();
      expect(json['code'], 'patch_invalid');
      final problems = (json['problems']! as List).cast<Map>();
      expect(problems.single['path'], 'entities[0].components.positon');
      expect(problems.single['message'], contains('did you mean "position"?'));
    }
  });

  test('a structural patch fault has a code and no problems list', () {
    final e = WorldPatchException('"entities" must be a list');
    expect(e.toJson(), {
      'code': 'patch_invalid',
      'message': '"entities" must be a list',
    });
  });

  test('ComponentApplyException names the entity and component', () {
    final world = _world();
    final id = world.spawn();
    try {
      world.components.applyToEntity(id, {
        'position': {'x': 'oops', 'y': 1},
      });
      fail('expected a ComponentApplyException');
    } on ComponentApplyException catch (e) {
      final json = e.toJson();
      expect(json['code'], 'component_invalid');
      expect(json['entity'], id);
      expect(json['component'], 'position');
      expect(json['message'], isA<String>());
    }
  });

  test('a strict level failure lists located problems', () {
    final world = _world();
    try {
      Level.loadInto(world, {
        'entities': [
          {
            'components': {
              'velocty': {'x': 1, 'y': 1},
            },
          },
        ],
      }, strict: true);
      fail('expected a LevelLoadException');
    } on LevelLoadException catch (e) {
      expect(e.code, 'level_invalid');
      expect(e.problems.single.path, 'entities[0].components.velocty');
      expect(e.toJson()['problems'], hasLength(1));
      expect(e.message, contains('entities[0].components.velocty:'));
    }
  });
}
