import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/graph/graph_canvas_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('graph_canvas');
    path = '${dir.path}/dialogue.graph.json';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> openScreen(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(home: GraphCanvasScreen(graphPath: path)),
  );

  testWidgets('starts empty when the file does not exist yet', (
    tester,
  ) async {
    await openScreen(tester);
    expect(find.byKey(const Key('graph-no-selection')), findsOneWidget);
    expect(find.textContaining('graph-node-'), findsNothing);
  });

  testWidgets('Add node adds a node and selects it', (tester) async {
    await openScreen(tester);
    await tester.tap(find.byKey(const Key('graph-add-node')));
    await tester.pump();

    expect(find.byKey(const Key('graph-node-say0')), findsOneWidget);
    expect(find.byKey(const Key('graph-no-selection')), findsNothing);
  });

  testWidgets('clicking an output then a matching input connects them', (
    tester,
  ) async {
    await openScreen(tester);
    await tester.tap(find.byKey(const Key('graph-add-node')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('graph-add-node')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('graph-port-say0-out-out')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('graph-port-say1-in-in')));
    await tester.pump();

    expect(find.byKey(const Key('graph-port-error')), findsNothing);
  });

  testWidgets('a type-mismatched connection shows an error banner', (
    tester,
  ) async {
    await openScreen(tester);
    // say (flow out) ...
    await tester.tap(find.byKey(const Key('graph-add-node')));
    await tester.pump();
    // ... then a branch (boolean condition input).
    await tester.tap(find.byKey(const Key('graph-add-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('branch').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('graph-add-node')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('graph-port-say0-out-out')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('graph-port-branch1-condition-in')));
    await tester.pump();

    expect(find.byKey(const Key('graph-port-error')), findsOneWidget);
    expect(find.textContaining('cannot connect'), findsOneWidget);
  });

  testWidgets('Save writes the graph, and reopening loads it back', (
    tester,
  ) async {
    await openScreen(tester);
    await tester.tap(find.byKey(const Key('graph-add-node')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('graph-save')));
    await tester.pump();

    expect(File(path).existsSync(), isTrue);
    final saved = jsonDecode(File(path).readAsStringSync()) as Map;
    expect((saved['graph'] as Map)['nodes'], hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await openScreen(tester);
    expect(find.byKey(const Key('graph-node-say0')), findsOneWidget);
  });

  testWidgets('an unreachable node shows up in the validation panel', (
    tester,
  ) async {
    await openScreen(tester);
    await tester.tap(find.byKey(const Key('graph-add-node')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('graph-add-node')));
    await tester.pump();
    // Two say nodes, never connected: the second is unreachable from the
    // first (which became the entry automatically).

    expect(find.byKey(const Key('graph-validation-panel')), findsOneWidget);
    expect(find.textContaining('not reachable'), findsOneWidget);
  });
}
