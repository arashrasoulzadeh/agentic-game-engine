import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/graph/graph_canvas_screen.dart';
import 'package:engine_studio/src/level/level_screen.dart';
import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Directory _project() {
  final root = Directory.systemTemp.createTempSync('a11y');
  File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
  Directory('${root.path}/lib').createSync();
  Directory('${root.path}/assets/levels').createSync(recursive: true);
  File('${root.path}/assets/levels/one.level.json').writeAsStringSync(
    jsonEncode({
      'entities': [
        {
          'name': 'p',
          'components': {
            'position': {'x': 8.0, 'y': 8.0},
          },
        },
      ],
    }),
  );
  return root;
}

void main() {
  testWidgets('project window: every tap target is labelled and large enough', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final root = _project();
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectScreen(
          project: StudioProject.open(root.path),
          useLanguageServer: false,
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('level editor: every tap target is labelled', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    final root = _project();
    addTearDown(() => root.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(
        home: LevelScreen(
          levelPath: '${root.path}/assets/levels/one.level.json',
          projectRoot: root.path,
          autosaveInterval: null,
        ),
      ),
    );
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('graph editor: every tap target is labelled', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    final dir = Directory.systemTemp.createTempSync('a11y_graph');
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(home: GraphCanvasScreen(graphPath: '${dir.path}/g.json')),
    );
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
