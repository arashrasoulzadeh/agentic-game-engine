import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String path;
  setUp(() {
    root = Directory.systemTemp.createTempSync('editor_gutter');
    path = '${root.path}/a.txt';
    File(path).writeAsStringSync('one\ntwo\nthree\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('shows one line number per line, including the trailing blank line', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodeEditorScreen(filePath: path, useLanguageServer: false),
      ),
    );
    expect(find.byKey(const Key('gutter-line-1')), findsOneWidget);
    expect(find.byKey(const Key('gutter-line-2')), findsOneWidget);
    expect(find.byKey(const Key('gutter-line-3')), findsOneWidget);
    expect(find.byKey(const Key('gutter-line-4')), findsOneWidget);
    expect(find.byKey(const Key('gutter-line-5')), findsNothing);
  });

  testWidgets('a line typed into the buffer gets its own gutter number', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodeEditorScreen(filePath: path, useLanguageServer: false),
      ),
    );
    await tester.enterText(find.byKey(const Key('code-text')), 'one\ntwo\n');
    await tester.pump();
    expect(find.byKey(const Key('gutter-line-3')), findsOneWidget);
    expect(find.byKey(const Key('gutter-line-4')), findsNothing);
  });
}
