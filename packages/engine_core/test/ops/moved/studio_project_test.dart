import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('studio_open'));
  tearDown(() => root.deleteSync(recursive: true));

  void makeProject({
    bool pubspec = true,
    bool levels = false,
    bool idle = false,
    bool gameConfig = false,
    bool bareAssets = false,
  }) {
    if (pubspec) {
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: my_game\n');
    }
    if (levels) {
      Directory('${root.path}/assets/levels').createSync(recursive: true);
    }
    if (idle) {
      Directory('${root.path}/assets').createSync(recursive: true);
      File('${root.path}/assets/idle_game.json').writeAsStringSync('{}');
    }
    if (gameConfig) {
      Directory('${root.path}/assets').createSync(recursive: true);
      File('${root.path}/assets/game_config.json').writeAsStringSync('{}');
    }
    if (bareAssets) {
      Directory('${root.path}/assets').createSync(recursive: true);
    }
  }

  test('opens a folder with a pubspec and a levels folder', () {
    makeProject(levels: true);
    final project = StudioProject.open(root.path);
    expect(project.root, root.absolute.path);
  });

  test('opens an idle project (idle_game.json, no levels)', () {
    makeProject(idle: true);
    expect(StudioProject.open(root.path).levelPaths(), isEmpty);
  });

  test('opens a strategy project (game_config.json, no levels)', () {
    makeProject(gameConfig: true);
    expect(isGameProjectRoot(root.path), isTrue);
    expect(StudioProject.open(root.path).levelPaths(), isEmpty);
  });

  test('opens a project with a bare assets folder', () {
    makeProject(bareAssets: true);
    expect(StudioProject.open(root.path).root, root.absolute.path);
  });

  test('rejects a missing folder with a message that names it', () {
    expect(
      () => StudioProject.open('${root.path}/nope'),
      throwsA(
        isA<ProjectOpenException>().having(
          (e) => e.message,
          'message',
          contains('does not exist'),
        ),
      ),
    );
  });

  test('rejects a folder with no pubspec.yaml', () {
    makeProject(levels: true, pubspec: false);
    expect(
      () => StudioProject.open(root.path),
      throwsA(
        isA<ProjectOpenException>().having(
          (e) => e.message,
          'message',
          contains('no pubspec.yaml'),
        ),
      ),
    );
  });

  test('rejects a pubspec-only folder with no game assets', () {
    makeProject();
    expect(
      () => StudioProject.open(root.path),
      throwsA(
        isA<ProjectOpenException>().having(
          (e) => e.message,
          'message',
          contains('no game assets'),
        ),
      ),
    );
  });

  test('lists level files, sorted, relative to the project root', () {
    makeProject(levels: true);
    final levels = Directory('${root.path}/assets/levels')
      ..createSync(recursive: true);
    File('${levels.path}/b.json').writeAsStringSync('{}');
    File('${levels.path}/a.json').writeAsStringSync('{}');
    File('${levels.path}/notes.txt').writeAsStringSync('');
    expect(StudioProject.open(root.path).levelPaths(), [
      'assets/levels/a.json',
      'assets/levels/b.json',
    ]);
  });
}
