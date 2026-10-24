import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('symbols');
    Directory('${root.path}/lib').createSync();
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    File('${root.path}/lib/hero.dart').writeAsStringSync(
      'abstract class HeroBase {}\nfinal class Hero extends HeroBase {}\n',
    );
    File('${root.path}/assets/levels/a.level.json').writeAsStringSync(
      '{"entities": [{"name": "heroSpawn", "components": {}}]}',
    );
    File('${root.path}/assets/studio_atlases.json').writeAsStringSync(
      '{"atlases": {"prisonTiles": {"image": "a.png", "manifest": "a.json"}}}',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'discovers the classes, atlas ids, and entity names a project defines',
    () {
      final symbols = ProjectSymbols.scan(root.path);
      expect(symbols.classes, containsAll(['HeroBase', 'Hero']));
      expect(symbols.atlasIds, {'prisonTiles'});
      expect(symbols.entityNames, {'heroSpawn'});
      expect(
        symbols.components,
        contains('position'),
        reason: 'engine components are known',
      );
    },
  );

  test(
    'completions match the typed prefix, and an empty prefix offers nothing',
    () {
      final symbols = ProjectSymbols.scan(root.path);
      expect(
        symbols.completionsFor('Her').map((c) => c.$1),
        containsAll(['Hero', 'HeroBase']),
      );
      expect(
        symbols.completionsFor('Her').map((c) => c.$1),
        isNot(contains('heroSpawn')),
      );
      expect(symbols.completionsFor(''), isEmpty);
    },
  );

  test('a project with missing folders still scans without failing', () {
    final empty = Directory.systemTemp.createTempSync('symbols_empty');
    addTearDown(() => empty.deleteSync(recursive: true));
    expect(ProjectSymbols.scan(empty.path).classes, isEmpty);
  });
}
