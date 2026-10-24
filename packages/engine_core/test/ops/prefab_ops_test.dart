import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

const lv = 'assets/levels/level1.json';

void main() {
  test(
    'save captures entities relative to their corner and list/read find it',
    () async {
      final s = await Scratch.create();
      expect(await s.data('prefab.list'), isEmpty);
      final saved = await s.map('prefab.save', {
        'path': lv,
        'name': 'pair',
        'entities': ['player', 'coin_1'],
      });
      expect(saved, {'path': 'prefabs/pair.json', 'entities': 2});
      final list = await s.data('prefab.list') as List;
      expect((list.single as Map)['name'], 'pair');
      final prefab = await s.map('prefab.read', {'name': 'pair'});
      final positions = [
        for (final e in prefab['entities']! as List)
          (e as Map)['components']['position'],
      ];
      expect(positions, [
        {'x': 0.0, 'y': 0.0},
        {'x': 16.0, 'y': 0.0},
      ]);
      expect(
        (await s.map('project.info'))['counts'],
        containsPair('prefabs', 1),
      );
    },
  );

  test(
    'place adds uniquely named copies at the target and is undoable',
    () async {
      final s = await Scratch.create();
      await s.data('prefab.save', {
        'path': lv,
        'name': 'pair',
        'entities': ['player', 'coin_1'],
      });
      final before = s.read(lv);
      final placed = await s.map('prefab.place', {
        'path': lv,
        'prefab': 'pair',
        'x': 100,
        'y': 50,
      });
      final names = [
        for (final e in placed['entities']! as List) (e as Map)['name'],
      ];
      expect(names, ['player2', 'coin_12']);
      final entities = (jsonDecode(s.read(lv))['entities'] as List).length;
      expect(entities, 5);
      await s.data('undo.undo');
      expect(s.read(lv), before);
    },
  );

  test('bad names and missing things are reported', () async {
    final s = await Scratch.create();
    expect(
      await s.failure('prefab.read', {'name': 'nope'}),
      ErrorCode.notFound,
    );
    expect(
      await s.failure('prefab.read', {'name': '../x'}),
      ErrorCode.invalidParams,
    );
    expect(
      await s.failure('prefab.save', {
        'path': lv,
        'name': 'bad name',
        'entities': ['player'],
      }),
      ErrorCode.invalidParams,
    );
    expect(
      await s.failure('prefab.save', {
        'path': lv,
        'name': 'ok',
        'entities': ['ghost'],
      }),
      ErrorCode.notFound,
    );
    expect(
      await s.failure('prefab.place', {'path': lv, 'prefab': 'missing'}),
      ErrorCode.notFound,
    );
  });
}
