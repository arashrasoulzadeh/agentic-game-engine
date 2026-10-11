import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String path;
  setUp(() {
    root = Directory.systemTemp.createTempSync('bracket_highlight');
    path = '${root.path}/a.dart';
    File(path).writeAsStringSync('void run() {\n  var x = 1;\n}\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets(
    'moving the cursor next to a bracket does not crash the editor',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CodeEditorScreen(filePath: path, useLanguageServer: false),
        ),
      );
      final field = tester.widget<TextField>(find.byKey(const Key('code-text')));
      final controller = field.controller!;
      // Right after the '(' in "run(".
      controller.selection = const TextSelection.collapsed(offset: 9);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a file with no file extension completion issues still loads', (
    tester,
  ) async {
    // A plain regression guard: non-Dart files have no DartHighlightController
    // and so no bracket marks, which must not be assumed present.
    final plain = '${root.path}/b.txt';
    File(plain).writeAsStringSync('f(x)');
    await tester.pumpWidget(
      MaterialApp(
        home: CodeEditorScreen(filePath: plain, useLanguageServer: false),
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
