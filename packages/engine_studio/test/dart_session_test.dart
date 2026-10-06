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

  test(
    'the server reports a live error for an undefined name, as the file changes',
    () async {
      final session = await DartSession.open(root.path);
      final file = '${root.path}/lib/broken.dart';
      session.openFile(file, 'void run() {}\n');
      final events = session.diagnosticsFor(file);
      session.change(file, 'void run() { print(nothere); }\n');

      final found = await events
          .firstWhere((list) => list.isNotEmpty)
          .timeout(const Duration(seconds: 60));
      expect(found.single.isError, isTrue);
      expect(found.single.message, contains('nothere'));
      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'go to definition finds the class a reference points at',
    () async {
      final session = await DartSession.open(root.path);
      final use = '${root.path}/lib/use.dart';
      const source = "import 'hero.dart';\nvoid run() {\n  Hero();\n}\n";
      session.openFile(use, source);

      SourceLocation? where;
      for (var attempt = 0; attempt < 40 && where == null; attempt++) {
        where = await session.definitionAt(use, 2, 3);
        if (where == null) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      expect(where, isNotNull);
      expect(where!.path, endsWith('hero.dart'));
      expect(where.line, 0, reason: 'class Hero is declared on the first line');
      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'formatting returns the server\'s formatted text',
    () async {
      final session = await DartSession.open(root.path);
      final file = '${root.path}/lib/messy.dart';
      const messy = 'void  f( int a ){print(a);}\n';
      session.openFile(file, messy);

      String? formatted;
      for (var attempt = 0; attempt < 40 && formatted == null; attempt++) {
        formatted = await session.formatted(file, messy);
        if (formatted == null) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
      expect(formatted, isNotNull);
      expect(formatted, isNot(messy));
      expect(formatted, contains('void f(int a) {'));
      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
