import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String path;
  setUp(() {
    root = Directory.systemTemp.createTempSync('auto_close_editor');
    path = '${root.path}/a.dart';
    File(path).writeAsStringSync('');
  });
  tearDown(() => root.deleteSync(recursive: true));

  TextEditingController controllerOf(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('code-text'))).controller!;

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodeEditorScreen(filePath: path, useLanguageServer: false),
      ),
    );
    await tester.tap(find.byKey(const Key('code-text')));
    await tester.pump();
  }

  testWidgets('typing an open paren auto-closes it', (tester) async {
    await openEditor(tester);
    await tester.enterText(find.byKey(const Key('code-text')), '(');
    await tester.pump();
    final controller = controllerOf(tester);
    expect(controller.text, '()');
    expect(controller.selection, const TextSelection.collapsed(offset: 1));
  });

  testWidgets('typing the closing paren right after types through it', (
    tester,
  ) async {
    await openEditor(tester);
    final controller = controllerOf(tester);
    controller.value = const TextEditingValue(
      text: '()',
      selection: TextSelection.collapsed(offset: 1),
    );
    await tester.pump();
    // Simulate typing ')' at the cursor: the raw keystroke makes it "())"
    // with the cursor after the newly typed character, before auto-close
    // logic reacts.
    controller.value = const TextEditingValue(
      text: '())',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tester.pump();
    expect(controller.text, '()');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
  });

  testWidgets('Enter after an unclosed brace indents the new line', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(
      find.byKey(const Key('code-text')),
      'void run() {',
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    final controller = controllerOf(tester);
    expect(controller.text, 'void run() {\n  ');
  });

  testWidgets('Enter between an auto-closed empty brace pair splits it', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(find.byKey(const Key('code-text')), 'void run() ');
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('code-text')),
      'void run() {',
    );
    await tester.pump();
    final controller = controllerOf(tester);
    // Auto-close should have produced "void run() {}" with the cursor
    // between the braces.
    expect(controller.text, 'void run() {}');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.text, 'void run() {\n  \n}');
  });
}
