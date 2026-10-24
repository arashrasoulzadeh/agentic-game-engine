import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late ProjectRoot project;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ops_paths');
    Directory('${tmp.path}/project/assets/levels').createSync(recursive: true);
    File('${tmp.path}/project/assets/levels/a.json').writeAsStringSync('{}');
    Directory('${tmp.path}/outside').createSync();
    File('${tmp.path}/outside/secret.txt').writeAsStringSync('s');
    project = ProjectRoot('${tmp.path}/project');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void rejects(String path) {
    expect(
      () => project.resolve(path),
      throwsA(
        isA<OpError>().having((e) => e.code, 'code', ErrorCode.invalidParams),
      ),
      reason: path,
    );
  }

  test('relative paths resolve inside the project, existing or not', () {
    expect(
      project.resolve('assets/levels/a.json'),
      p.join(project.root, 'assets', 'levels', 'a.json'),
    );
    expect(
      project.resolve('assets/levels/new.json'),
      p.join(project.root, 'assets', 'levels', 'new.json'),
    );
    expect(
      project.resolve('./assets/../assets/levels/a.json'),
      p.join(project.root, 'assets', 'levels', 'a.json'),
    );
    expect(
      project.relativeOf(project.resolve('assets/levels/a.json')),
      'assets/levels/a.json',
    );
  });

  test('absolute, parent, empty, NUL and drive paths are refused', () {
    for (final bad in [
      '/etc/passwd',
      '../outside/secret.txt',
      'assets/../../outside',
      '',
      'a\u0000b',
      'C:/x',
      r'..\outside',
      'assets/levels/../../../x',
    ]) {
      rejects(bad);
    }
  });

  test('a symlink inside the project that leads outside is refused', () {
    Link('${tmp.path}/project/escape').createSync('${tmp.path}/outside');
    rejects('escape/secret.txt');
    rejects('escape');
    Link(
      '${tmp.path}/project/assets/alias',
    ).createSync('${tmp.path}/project/assets/levels');
    expect(
      project.resolve('assets/alias/a.json'),
      isNotEmpty,
      reason: 'a link that stays inside is fine',
    );
  });

  test('a nonexistent path below a link to the outside is refused too', () {
    Link('${tmp.path}/project/escape').createSync('${tmp.path}/outside');
    rejects('escape/new/file.txt');
  });
}
