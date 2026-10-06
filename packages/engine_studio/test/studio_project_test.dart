import 'dart:io';

import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('studio_open'));
  tearDown(() => root.deleteSync(recursive: true));

  void makeProject({bool pubspec = true, bool levels = true}) {
    if (pubspec) {
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: my_game\n');
    }
    if (levels) {
      Directory('${root.path}/assets/levels').createSync(recursive: true);
    }
  }

  test('opens a folder with a pubspec and a levels folder', () {
    makeProject();
    final project = StudioProject.open(root.path);
    expect(project.root, root.absolute.path);
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
    makeProject(pubspec: false);
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

  test('rejects a game project with no levels folder', () {
    makeProject(levels: false);
    expect(
      () => StudioProject.open(root.path),
      throwsA(
        isA<ProjectOpenException>().having(
          (e) => e.message,
          'message',
          contains('assets/levels'),
        ),
      ),
    );
  });

  test('lists level files, sorted, relative to the project root', () {
    makeProject();
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
