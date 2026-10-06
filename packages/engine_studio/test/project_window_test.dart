import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/code/analysis.dart';
import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('project_window');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
    Directory('${root.path}/lib').createSync();
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    File(
      '${root.path}/lib/main.dart',
    ).writeAsStringSync('void main() {\n  var x = 1;\n}\n');
    File(
      '${root.path}/assets/levels/a.level.json',
    ).writeAsStringSync('{"entities": []}');
  });
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets(
    'the file tree lists the project, and picking a Dart file opens it in the editor',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectScreen(project: StudioProject.open(root.path)),
        ),
      );
      expect(find.byKey(const Key('file-tree')), findsOneWidget);
      expect(find.byKey(const Key('no-file-open')), findsOneWidget);

      await tester.tap(find.byKey(const Key('file-lib')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('file-lib/main.dart')));
      await tester.pump();
      expect(find.byKey(const Key('code-text')), findsOneWidget);
    },
  );

  testWidgets(
    'analyze shows this file\'s findings, and tapping one moves the cursor to its line',
    (tester) async {
      final path = '${root.path}/lib/main.dart';
      await tester.pumpWidget(
        MaterialApp(
          home: CodeEditorScreen(
            filePath: path,
            projectRoot: root.path,
            analyzer: _FakeAnalyzer([
              AnalysisIssue(
                severity: AnalysisSeverity.error,
                code: 'UNDEFINED_IDENTIFIER',
                file: path,
                line: 2,
                column: 7,
                message: "Undefined name 'x'",
              ),
              AnalysisIssue(
                severity: AnalysisSeverity.warning,
                code: 'OTHER',
                file: '${root.path}/lib/other.dart',
                line: 1,
                column: 1,
                message: 'in another file',
              ),
            ]),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('code-analyze')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('analysis-panel')), findsOneWidget);
      expect(find.textContaining("Undefined name 'x'"), findsOneWidget);
      expect(
        find.textContaining('in another file'),
        findsNothing,
        reason: 'only this file\'s findings are shown here',
      );

      await tester.tap(find.byKey(const Key('finding-2-7')));
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const Key('code-text')),
      );
      expect(
        field.controller!.selection.baseOffset,
        'void main() {\n'.length,
        reason: 'the cursor is at the start of line 2',
      );
    },
  );

  testWidgets('the tree opens closed; tapping a folder expands it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ProjectScreen(project: StudioProject.open(root.path))),
    );
    expect(find.byKey(const Key('file-lib')), findsOneWidget);
    expect(find.byKey(const Key('file-lib/main.dart')), findsNothing);

    await tester.tap(find.byKey(const Key('file-lib')));
    await tester.pump();
    expect(find.byKey(const Key('file-lib/main.dart')), findsOneWidget);
  });

  testWidgets(
    'the Images filter lists only images, and an image opens in the viewer',
    (tester) async {
      _writeTinyPng('${root.path}/assets/logo.png');
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectScreen(project: StudioProject.open(root.path)),
        ),
      );

      await tester.tap(find.byKey(const Key('filter-image')));
      await tester.pump();
      expect(find.byKey(const Key('file-assets/logo.png')), findsOneWidget);
      expect(
        find.byKey(const Key('file-lib')),
        findsNothing,
        reason: 'the filter shows files only, not the tree',
      );

      await tester.tap(find.byKey(const Key('file-assets/logo.png')));
      await tester.pump();
      expect(find.byKey(const Key('image-view')), findsOneWidget);
      expect(find.text('logo.png'), findsOneWidget);
    },
  );
}

void _writeTinyPng(String path) {
  // A real 1x1 PNG, so the viewer has a valid image to decode.
  File(path).writeAsBytesSync(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
    ),
  );
}

class _FakeAnalyzer extends ProjectAnalyzer {
  final List<AnalysisIssue> issues;

  _FakeAnalyzer(this.issues);

  @override
  Future<List<AnalysisIssue>> analyze(String projectRoot) async => issues;
}
