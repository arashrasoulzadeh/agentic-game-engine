import 'dart:io';

import 'package:test/test.dart';

import 'support/run_studio.dart';

void main() {
  test('validate ignores the .studio undo journal next to a level', () async {
    final dir = Directory.systemTemp.createTempSync('journal');
    addTearDown(() => dir.deleteSync(recursive: true));
    final levels = Directory('${dir.path}/assets/levels')
      ..createSync(recursive: true);
    File('${levels.path}/level1.json').writeAsStringSync('{"entities": []}');
    Directory('${levels.path}/.studio/undo').createSync(recursive: true);
    File(
      '${levels.path}/.studio/undo/000001.json',
    ).writeAsStringSync('{"operation": "level.add_entity"}');

    expect(await runStudio(['validate', dir.path]), 0);
  });
}
