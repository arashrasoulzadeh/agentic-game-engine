import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// A copy of the default game's level template (engine_cli/templates). It uses
/// the legend-authored `tileMap` form, which `TileMap.fromJson` rewrites as
/// flat ids. The round-trip must not go through `TileMap`, or the designer's
/// ASCII art would be lost on save.
final _fixture = File('test/fixtures/main_level.json');

/// The studio's writer format: two-space indent, one key per line.
String _encode(Object? json) =>
    const JsonEncoder.withIndent('  ').convert(json);

void main() {
  test(
    'a legend-authored level keeps its data and key order through a save',
    () {
      final original =
          jsonDecode(_fixture.readAsStringSync()) as Map<String, dynamic>;
      final saved = _encode(LevelDocument.fromJson(original).toJson());

      expect(jsonDecode(saved), original);
      expect(
        (jsonDecode(saved)
            as Map)['entities'][0]['components']['tileMap']['rows'],
        isA<List>(),
        reason:
            'the ASCII rows must survive, not be rewritten as flat tile ids',
      );
    },
  );

  test('saving twice produces identical output, so the format is stable', () {
    final original =
        jsonDecode(_fixture.readAsStringSync()) as Map<String, dynamic>;
    final first = _encode(LevelDocument.fromJson(original).toJson());
    final second = _encode(
      LevelDocument.fromJson(
        jsonDecode(first) as Map<String, dynamic>,
      ).toJson(),
    );
    expect(second, first);
  });
}
