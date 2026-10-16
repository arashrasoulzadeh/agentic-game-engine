import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:engine_studio/src/lsp/dart_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('document_outline');
    File(
      '${root.path}/pubspec.yaml',
    ).writeAsStringSync('name: demo\nenvironment:\n  sdk: ^3.0.0\n');
    Directory('${root.path}/lib').createSync();
    File('${root.path}/lib/hero.dart').writeAsStringSync(
      'class Hero {\n  int health = 3;\n  void jump() {}\n}\n',
    );
  });
  tearDown(() => root.deleteSync(recursive: true));

  test(
    'the real server lists the class and its members, nested under it',
    () async {
      final session = await DartSession.open(root.path);
      final file = '${root.path}/lib/hero.dart';
      session.openFile(file, File(file).readAsStringSync());

      List<DocumentSymbolEntry> found = const [];
      for (var attempt = 0; attempt < 80 && found.isEmpty; attempt++) {
        try {
          found = await session.documentSymbols(file);
        } on Object {
          found = const [];
        }
        if (found.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }

      expect(found, isNotEmpty, reason: 'the server finds Hero and its members');
      final names = found.map((s) => s.name).toList();
      expect(names, containsAll(['Hero', 'health', 'jump']));

      final hero = found.firstWhere((s) => s.name == 'Hero');
      expect(hero.depth, 0, reason: 'the class itself is top-level');
      final health = found.firstWhere((s) => s.name == 'health');
      expect(
        health.depth,
        greaterThan(hero.depth),
        reason: 'a field is nested under its class',
      );

      await session.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'the outline button is absent with no language server',
    (tester) async {
      final path = '${root.path}/lib/hero.dart';
      await tester.pumpWidget(
        MaterialApp(
          home: CodeEditorScreen(filePath: path, useLanguageServer: false),
        ),
      );
      expect(find.byKey(const Key('code-outline')), findsNothing);
      expect(find.byKey(const Key('outline-panel')), findsNothing);
    },
  );
}
