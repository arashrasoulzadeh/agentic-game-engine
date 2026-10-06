import 'dart:io';

import 'package:engine_studio/src/lsp/dart_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('dart_session');
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\nenvironment:\n  sdk: ^3.0.0\n');
    Directory('${root.path}/lib').createSync();
    File('${root.path}/lib/hero.dart').writeAsStringSync(
      'class Hero {\n  void jump() {}\n  int health = 3;\n}\n',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'the real language server offers a class\'s members after a dot',
    () async {
      final session = await DartSession.open(root.path);
      final use = '${root.path}/lib/use.dart';
      const source =
          "import 'hero.dart';\nvoid run() {\n  final h = Hero();\n  h.\n}\n";
      session.openFile(use, source);

      // Line 3 (0-based), just after the dot.
      var items = await session.completionsAt(use, 3, 4);
      for (var attempt = 0; attempt < 40 && items.isEmpty; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        items = await session.completionsAt(use, 3, 4);
      }
      final labels = items.map((i) => i.insertText);
      expect(
        labels,
        containsAll(['jump', 'health']),
        reason: 'the analyzer knows Hero, so its members are offered',
      );
      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
