import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String path;
  setUp(() {
    root = Directory.systemTemp.createTempSync('unsaved_work_safety');
    path = '${root.path}/a.txt';
    File(path).writeAsStringSync('hello\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CodeEditorScreen(filePath: path, useLanguageServer: false),
      ),
    );
  }

  testWidgets('popping a clean file closes it with no dialog', (
    tester,
  ) async {
    await openEditor(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.maybePop();
    await tester.pump();
    expect(find.text('Discard unsaved changes?'), findsNothing);
  });

  testWidgets('popping a dirty file asks first, and Cancel keeps it open', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(find.byKey(const Key('code-text')), 'hello\nmore\n');
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.maybePop();
    await tester.pump();

    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(find.byKey(const Key('code-text')), findsOneWidget);
    expect(File(path).readAsStringSync(), 'hello\n');
  });

  testWidgets('choosing Discard closes the file without saving', (
    tester,
  ) async {
    await openEditor(tester);
    await tester.enterText(find.byKey(const Key('code-text')), 'hello\nmore\n');
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.maybePop();
    await tester.pump();

    await tester.tap(find.byKey(const Key('discard-changes')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('code-text')), findsNothing);
    expect(
      File(path).readAsStringSync(),
      'hello\n',
      reason: 'discarding never writes the file',
    );
  });
}
