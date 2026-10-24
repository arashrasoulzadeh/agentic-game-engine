import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('project_search');
    Directory('${root.path}/lib').createSync();
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    File(
      '${root.path}/lib/hero.dart',
    ).writeAsStringSync('class Hero {\n  void jump() {}\n}\n');
    File(
      '${root.path}/lib/enemy.dart',
    ).writeAsStringSync('class Enemy {\n  void jump() {}\n}\n');
    File('${root.path}/assets/levels/a.json').writeAsStringSync('{"jump": 1}');
    File('${root.path}/assets/sprite.png').writeAsBytesSync([0, 1, 2]);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('finds matches across every searchable file, in tree order', () {
    final entries = listProjectTree(root.path);
    final matches = searchProject(root.path, entries, 'jump');
    expect(matches.length, 3);
    expect(matches.every((m) => m.lineText.contains('jump')), isTrue);
  });

  test('reports the right file, line, and column for each match', () {
    final entries = listProjectTree(root.path);
    final matches = searchProject(root.path, entries, 'Hero');
    expect(matches.single.relativePath, 'lib/hero.dart');
    expect(matches.single.line, 0);
    expect(matches.single.character, 6);
  });

  test('an empty query has no matches', () {
    final entries = listProjectTree(root.path);
    expect(searchProject(root.path, entries, ''), isEmpty);
  });

  test('a binary file is skipped rather than crashing the search', () {
    final entries = listProjectTree(root.path);
    expect(() => searchProject(root.path, entries, 'png'), returnsNormally);
  });
}
