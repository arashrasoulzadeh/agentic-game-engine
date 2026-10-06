import 'dart:io';

import 'package:engine_studio/src/project/project_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('tree');
    for (final folder in [
      'lib/scenes',
      'assets/levels',
      'build',
      '.dart_tool',
      '.git',
    ]) {
      Directory('${root.path}/$folder').createSync(recursive: true);
    }
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
    File('${root.path}/.metadata').writeAsStringSync('');
    File('${root.path}/lib/main.dart').writeAsStringSync('');
    File('${root.path}/lib/scenes/hero.dart').writeAsStringSync('');
    File(
      '${root.path}/assets/levels/prison.level.json',
    ).writeAsStringSync('{}');
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('lists folders and files, folders first at each level, sorted', () {
    final paths = listProjectTree(
      root.path,
    ).map((e) => e.relativePath).toList();
    expect(paths, [
      'assets',
      'assets/levels',
      'assets/levels/prison.level.json',
      'lib',
      'lib/scenes',
      'lib/scenes/hero.dart',
      'lib/main.dart',
      'pubspec.yaml',
    ]);
  });

  test('leaves out generated folders, hidden folders, and hidden files', () {
    final names = listProjectTree(root.path).map((e) => e.name);
    expect(names, isNot(contains('build')));
    expect(names, isNot(contains('.dart_tool')));
    expect(names, isNot(contains('.git')));
    expect(names, isNot(contains('.metadata')));
  });

  test('an entry reports its depth for indenting', () {
    final entries = listProjectTree(root.path);
    expect(entries.firstWhere((e) => e.name == 'lib').depth, 0);
    expect(entries.firstWhere((e) => e.name == 'hero.dart').depth, 2);
  });

  test('a missing project lists nothing rather than failing', () {
    expect(listProjectTree('${root.path}/nope'), isEmpty);
  });
}
