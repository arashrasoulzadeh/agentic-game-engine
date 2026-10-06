import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

const _levelJson = {
  'entities': [
    {
      'name': 'player',
      'components': {
        'position': {'x': 10.0, 'y': 20.0},
      },
    },
    {
      'components': {
        'pushable': {'pushSpeed': 2.5},
      },
    },
  ],
};

void main() {
  group('LevelDocument.fromJson', () {
    test('parses entities, names, and components', () {
      final doc = LevelDocument.fromJson(_levelJson);
      expect(doc.entities, hasLength(2));
      expect(doc.entities[0].name, 'player');
      expect(doc.entities[0].components['position'], {'x': 10.0, 'y': 20.0});
      expect(doc.entities[1].name, isNull);
    });

    test(
      'rejects a structurally bad file with the runtime loader\'s exception',
      () {
        expect(
          () => LevelDocument.fromJson({'entities': 'nope'}),
          throwsA(isA<LevelLoadException>()),
        );
      },
    );

    test('throws when the entities key is missing', () {
      expect(
        () => LevelDocument.fromJson({}),
        throwsA(isA<LevelLoadException>()),
      );
    });
  });

  group('LevelDocument.toJson', () {
    test('round-trips unchanged data to equal JSON', () {
      final doc = LevelDocument.fromJson(_levelJson);
      expect(doc.toJson(), _levelJson);
    });

    test('omits name for an unnamed entity instead of writing null', () {
      final doc = LevelDocument.fromJson(_levelJson);
      final unnamed = doc.toJson()['entities'] as List;
      expect((unnamed[1] as Map).containsKey('name'), isFalse);
    });

    test('keeps component key order, so re-encoding is byte-stable', () {
      final first = jsonEncode(LevelDocument.fromJson(_levelJson).toJson());
      final second = jsonEncode(
        LevelDocument.fromJson(
          jsonDecode(first) as Map<String, dynamic>,
        ).toJson(),
      );
      expect(second, first);
    });
  });

  group('LevelDocument.entityNamed', () {
    test('finds an entity by name, or null when none has it', () {
      final doc = LevelDocument.fromJson(_levelJson);
      expect(doc.entityNamed('player')?.components.keys, ['position']);
      expect(doc.entityNamed('ghost'), isNull);
    });
  });
}
