import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/graph/graph_canvas_screen.dart';
import 'package:engine_studio/src/graph/graph_editor.dart';
import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wires `parent.children -> child.in` the way the canvas does, by clicking ports.
void _connect(GraphEditor e, String from, String fromPort, String to) {
  e.clickPort(from, fromPort, isOutput: true);
  e.clickPort(to, 'in', isOutput: false);
}

void main() {
  group('GraphDocument', () {
    test('the type is omitted for dialogue (existing files unchanged) and kept otherwise', () {
      final dialogue = GraphEditor().document.toJson();
      expect(dialogue.containsKey('type'), isFalse);
      expect(GraphDocument.fromJson(dialogue).type, GraphType.dialogue);

      final bt = GraphEditor(type: GraphType.behaviorTree).document.toJson();
      expect(bt['type'], 'behaviorTree');
      expect(GraphDocument.fromJson(bt).type, GraphType.behaviorTree);
      expect(GraphEditor.fromDocument(GraphDocument.fromJson(bt)).type, GraphType.behaviorTree);
    });

    test('a file with an unknown type opens as dialogue rather than failing', () {
      final doc = GraphDocument.fromJson({'type': 'hologram', 'graph': const Graph().toJson()});
      expect(doc.type, GraphType.dialogue);
    });
  });

  group('GraphEditor by type', () {
    test('each type brings its own node kinds', () {
      expect(GraphEditor().registry.keys, contains('say'));
      expect(GraphEditor(type: GraphType.behaviorTree).registry.keys, contains('sequence'));
      expect(GraphEditor(type: GraphType.stateMachine).registry.keys, containsAll(['state', 'transition']));
    });

    test('AI nodes start with their schema defaults; dialogue nodes start empty', () {
      final bt = GraphEditor(type: GraphType.behaviorTree);
      expect(bt.nodes, isEmpty);
      final w = bt.addNode('wait', Offset.zero);
      expect(w.params['duration'], 1.0);
      final parallel = bt.addNode('parallel', Offset.zero);
      expect(parallel.params['requiredSuccess'], 1);
      expect(bt.addNode('sequence', Offset.zero).params, isEmpty);

      expect(GraphEditor().addNode('say', Offset.zero).params, isEmpty);
    });

    test('a behavior tree validates as a tree, and compiles in canvas order', () {
      final e = GraphEditor(type: GraphType.behaviorTree);
      final root = e.addNode('sequence', const Offset(100, 0));
      final left = e.addNode('wait', const Offset(0, 100));
      final right = e.addNode('wait', const Offset(300, 100));
      expect(e.validate().map((i) => i.message), contains(contains('has no children')));

      // Connected right-then-left, but laid out left-then-right.
      _connect(e, root.id, 'children', right.id);
      _connect(e, root.id, 'children', left.id);
      expect(e.validate(), isEmpty);

      final json = e.compile()!;
      expect([for (final c in json['children'] as List) c['id']], [left.id, right.id],
          reason: 'children follow the canvas left to right, not the click order');
      expect(BTNode.fromJson(json), isA<BTSequence>());
    });

    test('compile reports a broken tree instead of producing JSON', () {
      final e = GraphEditor(type: GraphType.behaviorTree);
      e.addNode('inverter', Offset.zero);
      expect(() => e.compile(), throwsA(isA<GraphCompileException>()));
    });

    test('a state machine may loop, and compiles to a StateMachine the engine loads', () {
      final e = GraphEditor(type: GraphType.stateMachine);
      final a = e.addNode('state', const Offset(0, 0));
      final b = e.addNode('state', const Offset(300, 0));
      final t1 = e.addNode('transition', const Offset(150, -50));
      final t2 = e.addNode('transition', const Offset(150, 50));
      e.setParams(a.id, {'name': 'idle'});
      e.setParams(b.id, {'name': 'chase'});
      e.setParams(t1.id, {'condition': 'seesPlayer'});
      e.setParams(t2.id, {'condition': 'lostPlayer'});
      _connect(e, a.id, 'out', t1.id);
      _connect(e, t1.id, 'out', b.id);
      _connect(e, b.id, 'out', t2.id);
      _connect(e, t2.id, 'out', a.id);
      expect(e.validate(), isEmpty, reason: 'a loop is the point of a state machine');

      final fsm = StateMachine.fromJson(e.compile(id: 'guard')!, BehaviorRegistry());
      expect(fsm.currentStateName, 'idle');
      expect(fsm.states['idle']!.transitions.keys, ['chase']);
    });

    test('a dialogue graph has no single compiled form', () {
      expect(GraphEditor().compile(), isNull);
    });
  });

  group('importBehaviorTree', () {
    final tree = BTSelector(id: 'root', children: [
      BTSequence(id: 'a', children: [BTLeaf(id: 'x', behaviorId: 'act')]),
      BTWait(id: 'w', duration: 2),
    ]).toJson();

    test('fills an empty behavior-tree editor and compiles back to the same JSON', () {
      final e = GraphEditor(type: GraphType.behaviorTree);
      expect(e.importBehaviorTree(tree), isNull);
      expect(e.nodes, hasLength(4));
      expect(e.entryNodeId, 'root');
      expect(e.layout['root'], isNotNull);
      expect(jsonEncode(e.compile()), jsonEncode(tree));
    });

    test('refuses to overwrite work, the wrong graph type, and junk — with a reason, not an exception', () {
      final busy = GraphEditor(type: GraphType.behaviorTree)..addNode('wait', Offset.zero);
      expect(busy.importBehaviorTree(tree), contains('already has nodes'));
      expect(busy.nodes, hasLength(1), reason: 'nothing was touched');
      expect(GraphEditor().importBehaviorTree(tree), contains('only a behavior-tree graph'));
      expect(GraphEditor(type: GraphType.behaviorTree).importBehaviorTree({'type': 'banana'}),
          contains('not a behavior tree'));
    });
  });

  group('screens', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('ai_graphs');
      File('${dir.path}/pubspec.yaml').writeAsStringSync('name: g\n');
      Directory('${dir.path}/graphs').createSync();
      Directory('${dir.path}/assets/levels').createSync(recursive: true);
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> open(WidgetTester tester, String name, GraphType type) => tester.pumpWidget(
          MaterialApp(home: GraphCanvasScreen(graphPath: '${dir.path}/graphs/$name', newType: type)),
        );

    testWidgets('Export refuses a broken tree and says why; nothing is written', (tester) async {
      await open(tester, 'guard.json', GraphType.behaviorTree);
      expect(find.byKey(const Key('graph-export')), findsOneWidget);
      expect(find.byKey(const Key('graph-import')), findsOneWidget);

      // The first kind on offer is "sequence"; a root sequence with no children is an error.
      await tester.tap(find.byKey(const Key('graph-add-node')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('graph-export')));
      await tester.pump();

      expect(find.byKey(const Key('graph-tool-error')), findsOneWidget);
      expect(find.textContaining('has no children'), findsWidgets);
      expect(File('${dir.path}/assets/ai/guard.json').existsSync(), isFalse);
    });

    testWidgets('Export writes engine JSON the engine can load', (tester) async {
      final editor = GraphEditor(type: GraphType.behaviorTree);
      final root = editor.addNode('sequence', const Offset(0, 0));
      final wait = editor.addNode('wait', const Offset(0, 100));
      _connect(editor, root.id, 'children', wait.id);
      File('${dir.path}/graphs/guard.json').writeAsStringSync(jsonEncode(editor.document.toJson()));

      await open(tester, 'guard.json', GraphType.behaviorTree);
      await tester.tap(find.byKey(const Key('graph-export')));
      await tester.pump();

      expect(find.byKey(const Key('graph-tool-error')), findsNothing);
      expect(find.text('Exported to assets/ai/guard.json'), findsOneWidget);
      final exported = jsonDecode(File('${dir.path}/assets/ai/guard.json').readAsStringSync()) as Map<String, dynamic>;
      expect(exported['type'], 'sequence');
      expect(exported['children'][0], containsPair('duration', 1.0));
      expect(BTNode.fromJson(exported), isA<BTSequence>());
    });

    testWidgets('a dialogue graph has no export or import buttons', (tester) async {
      await open(tester, 'talk.json', GraphType.dialogue);
      expect(find.byKey(const Key('graph-export')), findsNothing);
      expect(find.byKey(const Key('graph-import')), findsNothing);
    });

    testWidgets('a state machine offers Export but not Import', (tester) async {
      await open(tester, 'brain.json', GraphType.stateMachine);
      expect(find.byKey(const Key('graph-export')), findsOneWidget);
      expect(find.byKey(const Key('graph-import')), findsNothing);
    });

    testWidgets('Import loads an engine behavior-tree file into an empty graph', (tester) async {
      Directory('${dir.path}/assets/ai').createSync(recursive: true);
      File('${dir.path}/assets/ai/existing.json').writeAsStringSync(jsonEncode(
        BTSequence(id: 'root', children: [BTWait(id: 'pause', duration: 3)]).toJson(),
      ));
      await open(tester, 'imported.json', GraphType.behaviorTree);
      await tester.tap(find.byKey(const Key('graph-import')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('graph-import-path')), 'assets/ai/existing.json');
      await tester.tap(find.byKey(const Key('graph-import-confirm')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('graph-tool-error')), findsNothing);
      expect(find.byKey(const Key('graph-node-root')), findsOneWidget);
      expect(find.byKey(const Key('graph-node-pause')), findsOneWidget);
    });

    testWidgets('Import explains a missing file or a non-tree instead of crashing', (tester) async {
      File('${dir.path}/notjson.txt').writeAsStringSync('hello');
      File('${dir.path}/array.json').writeAsStringSync('[1,2]');
      await open(tester, 'bad.json', GraphType.behaviorTree);

      Future<void> tryImport(String path) async {
        await tester.tap(find.byKey(const Key('graph-import')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('graph-import-path')), path);
        await tester.tap(find.byKey(const Key('graph-import-confirm')));
        await tester.pumpAndSettle();
      }

      await tryImport('nope.json');
      expect(find.textContaining('could not be read'), findsOneWidget);
      await tryImport('notjson.txt');
      expect(find.textContaining('is not valid JSON'), findsOneWidget);
      await tryImport('array.json');
      expect(find.textContaining('is not a behavior tree'), findsOneWidget);
    });

    testWidgets('Cancel leaves everything as it was', (tester) async {
      await open(tester, 'c.json', GraphType.behaviorTree);
      await tester.tap(find.byKey(const Key('graph-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('graph-tool-error')), findsNothing);
    });

    testWidgets('a state machine exports, resolving a state\'s behavior-tree graph', (tester) async {
      // A behavior-tree graph on disk for the state to reference.
      final bt = GraphEditor(type: GraphType.behaviorTree)..addNode('wait', Offset.zero);
      File('${dir.path}/graphs/patrol.json').writeAsStringSync(jsonEncode(bt.document.toJson()));

      final fsm = GraphEditor(type: GraphType.stateMachine);
      final s = fsm.addNode('state', Offset.zero);
      fsm.setParams(s.id, {'name': 'patrol', 'behaviorTreeGraph': 'graphs/patrol.json'});
      File('${dir.path}/graphs/brain.json').writeAsStringSync(jsonEncode(fsm.document.toJson()));

      await open(tester, 'brain.json', GraphType.stateMachine);
      await tester.tap(find.byKey(const Key('graph-export')));
      await tester.pump();

      final out = jsonDecode(File('${dir.path}/assets/ai/brain.json').readAsStringSync()) as Map<String, dynamic>;
      expect(out['id'], 'brain');
      expect(out['states']['patrol']['behaviorTree']['type'], 'wait');
    });

    testWidgets('the project window creates a behavior tree from the New graph menu', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ProjectScreen(project: StudioProject.open(dir.path), useLanguageServer: false),
      ));
      await tester.tap(find.byKey(const Key('project-new-graph')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('new-graph-behaviorTree')));
      await tester.pumpAndSettle();

      expect(find.byType(GraphCanvasScreen), findsOneWidget);
      expect(find.byKey(const Key('graph-export')), findsOneWidget);
      await tester.tap(find.byKey(const Key('graph-add-node')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('graph-save')));
      await tester.pump();
      final saved = jsonDecode(File('${dir.path}/graphs/graph1.json').readAsStringSync()) as Map;
      expect(saved['type'], 'behaviorTree');
    });
  });
}
