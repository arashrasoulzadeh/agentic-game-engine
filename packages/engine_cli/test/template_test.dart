import 'dart:io';

import 'package:engine_cli/src/template.dart';
import 'package:test/test.dart';

void main() {
  test('copyTemplate applies replacements and strips .tmpl suffix', () {
    final tmp = Directory.systemTemp.createTempSync('engine_cli_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final source = Directory('${tmp.path}/source')..createSync();
    File('${source.path}/pubspec.yaml.tmpl')
        .writeAsStringSync('name: {{PROJECT_NAME}}\n');
    Directory('${source.path}/lib').createSync();
    File('${source.path}/lib/main.dart.tmpl')
        .writeAsStringSync('// {{PROJECT_NAME}} entry point\n');

    final dest = Directory('${tmp.path}/dest');
    copyTemplate(source, dest, {'PROJECT_NAME': 'my_game'});

    expect(
      File('${dest.path}/pubspec.yaml').readAsStringSync(),
      'name: my_game\n',
    );
    expect(
      File('${dest.path}/lib/main.dart').readAsStringSync(),
      '// my_game entry point\n',
    );
    expect(File('${dest.path}/pubspec.yaml.tmpl').existsSync(), isFalse);
  });
}
