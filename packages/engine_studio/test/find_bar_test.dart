import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String path;
  setUp(() {
    root = Directory.systemTemp.createTempSync('find_bar');
    path = '${root.path}/a.txt';
    File(path).writeAsStringSync('one two one three one\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodeEditorScreen(filePath: path, useLanguageServer: false),
      ),
    );
    // The shortcuts only reach the editor once something inside it has
    // focus, as in the real app once the user clicks into it.
    await tester.tap(find.byKey(const Key('code-text')));
    await tester.pump();
  }

  Future<void> pressCtrlF(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  testWidgets('Ctrl+F opens the find bar', (tester) async {
    await openEditor(tester);
    expect(find.byKey(const Key('find-bar')), findsNothing);
    await pressCtrlF(tester);
    expect(find.byKey(const Key('find-bar')), findsOneWidget);
  });

  testWidgets('typing a query shows the match count', (tester) async {
    await openEditor(tester);
    await pressCtrlF(tester);
    await tester.enterText(find.byKey(const Key('find-input')), 'one');
    await tester.pump();
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('next/previous cycle through matches', (tester) async {
    await openEditor(tester);
    await pressCtrlF(tester);
    await tester.enterText(find.byKey(const Key('find-input')), 'one');
    await tester.pump();
    await tester.tap(find.byKey(const Key('find-next')));
    await tester.pump();
    expect(find.text('2/3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('find-prev')));
    await tester.pump();
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('Escape closes the find bar', (tester) async {
    await openEditor(tester);
    await pressCtrlF(tester);
    await tester.enterText(find.byKey(const Key('find-input')), 'one');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byKey(const Key('find-bar')), findsNothing);
  });

  testWidgets('Replace All replaces every match in the buffer', (tester) async {
    await openEditor(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byKey(const Key('replace-input')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('find-input')), 'one');
    await tester.pump();
    await tester.enterText(find.byKey(const Key('replace-input')), 'ONE');
    await tester.tap(find.byKey(const Key('replace-all')));
    await tester.pump();
    final field = tester.widget<TextField>(find.byKey(const Key('code-text')));
    expect(field.controller!.text, 'ONE two ONE three ONE\n');
  });
}
