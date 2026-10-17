import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/graph/graph_canvas_screen.dart';
import 'package:engine_studio/src/graph/graph_editor.dart';
import 'package:engine_studio/src/project/project_problems.dart';
import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/project_tree.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A project with one clean level, one level with a mistake, and graphs.
Directory _project() {
  final root = Directory.systemTemp.createTempSync('project_graphs');
  File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
  Directory('${root.path}/lib').createSync();
  Directory('${root.path}/assets/levels').createSync(recursive: true);
  File('${root.path}/assets/levels/ok.level.json').writeAsStringSync(
    jsonEncode({
      'entities': [
        {
          'name': 'player',
          'components': {
            'position': {'x': 1.0, 'y': 2.0},
          },
        },
      ],
    }),
  );
  return root;
}

String _graphJson({bool connected = true}) {
  final editor = GraphEditor();
  final a = editor.addNode('say', const Offset(0, 0));
  final b = editor.addNode('say', const Offset(200, 0));
  if (connected) {
    editor.clickPort(a.id, 'out', isOutput: true);
    editor.clickPort(b.id, 'in', isOutput: false);
  }
  return jsonEncode(editor.document.toJson());
}

void main() {
  late Directory root;
  setUp(() => root = _project());
  tearDown(() => root.deleteSync(recursive: true));

  group('graph files', () {
    test('graphPaths lists graphs/*.json sorted, and is empty when there is no folder', () {
      expect(StudioProject.open(root.path).graphPaths(), isEmpty);
      Directory('${root.path}/graphs').createSync();
      File('${root.path}/graphs/b.json').writeAsStringSync('{}');
      File('${root.path}/graphs/a.json').writeAsStringSync('{}');
      File('${root.path}/graphs/notes.txt').writeAsStringSync('x');
      expect(StudioProject.open(root.path).graphPaths(), ['graphs/a.json', 'graphs/b.json']);
    });

    test('nextGraphPath skips names that are taken', () {
      final project = StudioProject.open(root.path);
      expect(project.nextGraphPath(), 'graphs/graph1.json');
      Directory('${root.path}/graphs').createSync();
      File('${root.path}/graphs/graph1.json').writeAsStringSync('{}');
      File('${root.path}/graphs/graph2.json').writeAsStringSync('{}');
      expect(project.nextGraphPath(), 'graphs/graph3.json');
    });

    test('JSON under graphs/ is a graph, not generic data; elsewhere it is unchanged', () {
      FileKind kind(String path) => kindOf(ProjectEntry(path, isDirectory: false));
      expect(kind('graphs/dialogue.json'), FileKind.graph);
      expect(kind('graphs/sub/deep.json'), FileKind.graph);
      expect(kind('assets/levels/a.json'), FileKind.level);
      expect(kind('assets/data.json'), FileKind.data);
    });
  });

  group('collectProjectProblems', () {
    test('a clean project has none', () {
      Directory('${root.path}/graphs').createSync();
      File('${root.path}/graphs/ok.json').writeAsStringSync(_graphJson());
      expect(collectProjectProblems(StudioProject.open(root.path)), isEmpty);
    });

    test('level and graph problems are listed together, each tagged with its file and source', () {
      File('${root.path}/assets/levels/bad.level.json').writeAsStringSync(
        jsonEncode({
          'entities': [
            {
              'name': 'x',
              'components': {
                'position': {'x': 'not a number', 'y': 0},
              },
            },
          ],
        }),
      );
      Directory('${root.path}/graphs').createSync();
      File('${root.path}/graphs/loose.json').writeAsStringSync(_graphJson(connected: false));

      final problems = collectProjectProblems(StudioProject.open(root.path));
      final levelProblems = problems.where((p) => p.source == ProblemSource.level).toList();
      final graphProblems = problems.where((p) => p.source == ProblemSource.graph).toList();

      expect(levelProblems, isNotEmpty);
      expect(levelProblems.every((p) => p.file == 'assets/levels/bad.level.json'), isTrue);
      expect(levelProblems.first.isError, isTrue);
      expect(graphProblems.single.file, 'graphs/loose.json');
      expect(graphProblems.single.message, contains('not reachable'));
      expect(graphProblems.single.isError, isFalse, reason: 'an unreachable node is a warning');
      expect(graphProblems.single.nodeId, isNotNull);
      expect(problems.indexOf(levelProblems.first), lessThan(problems.indexOf(graphProblems.first)),
          reason: 'levels are listed first');
    });

    test('unreadable and malformed files are reported, not thrown', () {
      File('${root.path}/assets/levels/broken.level.json').writeAsStringSync('{ not json');
      File('${root.path}/assets/levels/array.level.json').writeAsStringSync('[1,2]');
      Directory('${root.path}/graphs').createSync();
      File('${root.path}/graphs/broken.json').writeAsStringSync('nope');
      File('${root.path}/graphs/shape.json').writeAsStringSync('{"graph": 7}');

      final problems = collectProjectProblems(StudioProject.open(root.path));
      final byFile = {for (final p in problems) p.file: p};
      expect(byFile['assets/levels/broken.level.json']!.message, contains('not valid JSON'));
      expect(byFile['assets/levels/array.level.json']!.message, contains('not a JSON object'));
      expect(byFile['graphs/broken.json']!.message, contains('not valid JSON'));
      expect(byFile['graphs/shape.json']!.message, contains('not a valid graph'));
      expect(problems.every((p) => p.isError), isTrue);
      expect(problems.first.toString(), contains(': '));
    });
  });

  group('project window', () {
    Future<void> open(WidgetTester tester) => tester.pumpWidget(
          MaterialApp(
            home: ProjectScreen(project: StudioProject.open(root.path), useLanguageServer: false),
          ),
        );

    testWidgets('the Graphs filter lists graphs and picking one opens the graph editor', (tester) async {
      Directory('${root.path}/graphs').createSync();
      File('${root.path}/graphs/talk.json').writeAsStringSync(_graphJson());
      await open(tester);

      await tester.tap(find.byKey(const Key('filter-graph')));
      await tester.pump();
      expect(find.byKey(const Key('file-graphs/talk.json')), findsOneWidget);
      await tester.tap(find.byKey(const Key('file-graphs/talk.json')));
      await tester.pump();

      expect(find.byType(GraphCanvasScreen), findsOneWidget);
      expect(find.byKey(const Key('graph-node-say0')), findsOneWidget);
      expect(find.byKey(const Key('graph-node-say1')), findsOneWidget);
    });

    testWidgets('New graph opens an empty editor for the next free name; saving creates the file', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('project-new-graph')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-graph-dialogue')));
      await tester.pumpAndSettle();

      expect(find.byType(GraphCanvasScreen), findsOneWidget);
      expect(find.text('graph1.json'), findsOneWidget);
      expect(File('${root.path}/graphs/graph1.json').existsSync(), isFalse, reason: 'nothing on disk until saved');

      await tester.tap(find.byKey(const Key('graph-add-node')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('graph-save')));
      await tester.pump();
      expect(File('${root.path}/graphs/graph1.json').existsSync(), isTrue);
    });

    testWidgets('the Problems panel summarises level and graph errors; tapping one opens its file', (tester) async {
      Directory('${root.path}/graphs').createSync();
      File('${root.path}/graphs/loose.json').writeAsStringSync(_graphJson(connected: false));
      File('${root.path}/assets/levels/ok.level.json').writeAsStringSync(
        jsonEncode({
          'entities': [
            {
              'name': 'x',
              'components': {
                'position': {'x': 'bad', 'y': 0},
              },
            },
          ],
        }),
      );
      await open(tester);
      await tester.tap(find.byKey(const Key('project-problems')));
      await tester.pump();

      expect(find.byKey(const Key('project-problems-panel')), findsOneWidget);
      expect(find.byKey(const Key('project-problems-summary')), findsOneWidget);
      expect(find.textContaining('error(s)'), findsOneWidget);
      expect(find.textContaining('graph · graphs/loose.json'), findsOneWidget);
      expect(find.textContaining('level · assets/levels/ok.level.json'), findsOneWidget);

      await tester.tap(find.textContaining('graph · graphs/loose.json'));
      await tester.pump();
      expect(find.byType(GraphCanvasScreen), findsOneWidget);
      expect(find.byKey(const Key('project-problems-panel')), findsNothing, reason: 'the panel closes');
    });

    testWidgets('a clean project says so, and the panel toggles closed', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('project-problems')));
      await tester.pump();
      expect(find.text('No problems in any level or graph'), findsOneWidget);
      await tester.tap(find.byKey(const Key('project-problems-close')));
      await tester.pump();
      expect(find.byKey(const Key('project-problems-panel')), findsNothing);
      expect(find.byKey(const Key('file-tree')), findsOneWidget);
    });

    testWidgets('opening search closes the problems panel and vice versa', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('project-problems')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('project-search')));
      await tester.pump();
      expect(find.byKey(const Key('project-problems-panel')), findsNothing);
      expect(find.byKey(const Key('project-search-panel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('project-problems')));
      await tester.pump();
      expect(find.byKey(const Key('project-search-panel')), findsNothing);
      expect(find.byKey(const Key('project-problems-panel')), findsOneWidget);
    });
  });
}
