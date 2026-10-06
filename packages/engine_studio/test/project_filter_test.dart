import 'dart:io';

import 'package:engine_studio/src/project/project_tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('filter');
    Directory('${root.path}/lib/scenes').createSync(recursive: true);
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    File('${root.path}/lib/main.dart').writeAsStringSync('');
    File('${root.path}/lib/scenes/hero.dart').writeAsStringSync('');
    File(
      '${root.path}/assets/levels/prison.level.json',
    ).writeAsStringSync('{}');
    File('${root.path}/assets/tiles.json').writeAsStringSync('{}');
    File('${root.path}/assets/tiles.png').writeAsStringSync('');
    File('${root.path}/pubspec.yaml').writeAsStringSync('');
  });
  tearDown(() => root.deleteSync(recursive: true));

  List<ProjectEntry> all() => listProjectTree(root.path);

  test('the tree starts closed: only the top level shows', () {
    final shown = visibleTree(all(), {}).map((e) => e.relativePath);
    expect(shown, containsAll(['assets', 'lib', 'pubspec.yaml']));
    expect(shown, isNot(contains('lib/main.dart')));
  });

  test(
    'expanding a folder shows its children, and a nested folder must be expanded too',
    () {
      expect(
        visibleTree(all(), {'lib'}).map((e) => e.relativePath),
        contains('lib/main.dart'),
      );
      final oneLevel = visibleTree(all(), {'lib'}).map((e) => e.relativePath);
      expect(
        oneLevel,
        isNot(contains('lib/scenes/hero.dart')),
        reason: 'lib/scenes is still closed',
      );
      final twoLevels = visibleTree(all(), {
        'lib',
        'lib/scenes',
      }).map((e) => e.relativePath);
      expect(twoLevels, contains('lib/scenes/hero.dart'));
    },
  );

  test('each file gets its filter kind', () {
    final kinds = {for (final e in all()) e.relativePath: kindOf(e)};
    expect(kinds['lib/main.dart'], FileKind.code);
    expect(kinds['assets/levels/prison.level.json'], FileKind.level);
    expect(kinds['assets/tiles.json'], FileKind.data);
    expect(kinds['assets/tiles.png'], FileKind.image);
    expect(kinds['pubspec.yaml'], FileKind.data);
  });

  test('a type filter lists only that type, flat', () {
    expect(filterFiles(all(), FileKind.code).map((e) => e.relativePath), [
      'lib/scenes/hero.dart',
      'lib/main.dart',
    ]);
    expect(filterFiles(all(), FileKind.image).map((e) => e.relativePath), [
      'assets/tiles.png',
    ]);
    expect(
      filterFiles(all(), FileKind.all),
      isEmpty,
      reason: 'the all filter is the tree, not a flat list',
    );
  });
}
