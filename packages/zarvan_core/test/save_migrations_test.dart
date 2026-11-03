import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

Map<String, dynamic> _v1() => {
  'entities': [
    {
      'id': 1,
      'components': {
        'health': {'health': 5},
      },
    },
    {'id': 2, 'components': <String, dynamic>{}},
  ],
};

void main() {
  SaveMigrations chain() => SaveMigrations()
    ..step(1, (w) => SaveMigrations.renameField(w, 'health', 'health', 'hp'))
    ..step(2, (w) => SaveMigrations.renameComponent(w, 'health', 'life'))
    ..step(3, (w) => SaveMigrations.addField(w, 'life', 'max', 10));

  test('steps chain from the saved version to the target', () {
    final out = chain().migrate(_v1(), 1, 4);
    final c = (out['entities'] as List).first['components'] as Map;
    expect(c['life'], {'hp': 5, 'max': 10});
    expect(c.containsKey('health'), isFalse);
  });

  test('starting part-way only runs the later steps', () {
    final v3 = {
      'entities': [
        {
          'id': 1,
          'components': {
            'life': {'hp': 2},
          },
        },
      ],
    };
    final out = chain().migrate(v3, 3, 4);
    expect((out['entities'] as List).first['components']['life']['max'], 10);
  });

  test('the input is not modified, and a gap or newer save is reported', () {
    final input = _v1();
    chain().migrate(input, 1, 4);
    expect((input['entities'] as List).first['components'], contains('health'));
    expect(() => SaveMigrations().migrate(_v1(), 1, 2), throwsStateError);
    expect(() => chain().migrate(_v1(), 5, 4), throwsStateError);
    expect(() => chain().step(1, (w) => w), throwsArgumentError);
  });

  test('forVersion fits the SaveGame.load migrate callback', () {
    final fn = chain().forVersion(4);
    expect(fn(_v1(), 1)['entities'], isNotEmpty);
  });
}
