import 'dart:io';

import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('find_in_project');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
    Directory('${root.path}/lib').createSync();
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    File(
      '${root.path}/lib/hero.dart',
    ).writeAsStringSync('class Hero {\n  void jump() {}\n}\n');
    File(
      '${root.path}/lib/enemy.dart',
    ).writeAsStringSync('class Enemy {\n  void jump() {}\n}\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> openProject(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectScreen(
          project: StudioProject.open(root.path),
          useLanguageServer: false,
        ),
      ),
    );
  }

  testWidgets('the search icon opens the find-in-project panel', (
    tester,
  ) async {
    await openProject(tester);
    expect(find.byKey(const Key('project-search-panel')), findsNothing);
    await tester.tap(find.byKey(const Key('project-search')));
    await tester.pump();
    expect(find.byKey(const Key('project-search-panel')), findsOneWidget);
  });

  testWidgets('Cmd/Ctrl+Shift+F opens the panel too', (tester) async {
    await openProject(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byKey(const Key('project-search-panel')), findsOneWidget);
  });

  testWidgets('typing a query lists matches across files, with a count', (
    tester,
  ) async {
    await openProject(tester);
    await tester.tap(find.byKey(const Key('project-search')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('project-search-input')),
      'jump',
    );
    await tester.pump();
    expect(find.text('2 match(es)'), findsOneWidget);
  });

  testWidgets('tapping a result opens that file in the code editor', (
    tester,
  ) async {
    await openProject(tester);
    await tester.tap(find.byKey(const Key('project-search')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('project-search-input')),
      'Enemy',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(
        const Key('project-match-lib/enemy.dart-0-6'),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('code-text')), findsOneWidget);
  });

  testWidgets('the close button returns to the file tree', (tester) async {
    await openProject(tester);
    await tester.tap(find.byKey(const Key('project-search')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('project-search-close')));
    await tester.pump();
    expect(find.byKey(const Key('file-tree')), findsOneWidget);
  });
}
