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

  Future<void> openScreen(WidgetTester tester) =>
      tester.pumpWidget(MaterialApp(home: GraphCanvasScreen(graphPath: path)));

  testWidgets('starts empty when the file does not exist yet', (tester) async {
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

  group('pan and zoom', () {
    double zoomOf(WidgetTester tester) => tester
        .widget<InteractiveViewer>(find.byKey(const Key('graph-canvas-viewer')))
        .transformationController!
        .value
        .getMaxScaleOnAxis();

    double nodeLeft(WidgetTester tester, String id) => tester
        .widget<Positioned>(
          find.ancestor(
            of: find.byKey(Key('graph-node-$id')),
            matching: find.byType(Positioned),
          ),
        )
        .left!;

    testWidgets('the buttons zoom in and out and the range is clamped', (
      tester,
    ) async {
      await openScreen(tester);
      expect(zoomOf(tester), 1);
      await tester.tap(find.byKey(const Key('graph-zoom-in')));
      await tester.pump();
      expect(zoomOf(tester), closeTo(1.25, 1e-9));
      await tester.tap(find.byKey(const Key('graph-zoom-out')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('graph-zoom-out')));
      await tester.pump();
      expect(zoomOf(tester), closeTo(0.8, 1e-9));

      for (var i = 0; i < 20; i++) {
        await tester.tap(find.byKey(const Key('graph-zoom-in')));
      }
      await tester.pump();
      expect(
        zoomOf(tester),
        closeTo(2.5, 1e-9),
        reason: 'never beyond the maximum',
      );
      for (var i = 0; i < 40; i++) {
        await tester.tap(find.byKey(const Key('graph-zoom-out')));
      }
      await tester.pump();
      expect(
        zoomOf(tester),
        closeTo(0.25, 1e-9),
        reason: 'never below the minimum',
      );
    });

    testWidgets('a node follows the pointer proportionally at any zoom', (
      tester,
    ) async {
      await openScreen(tester);
      await tester.tap(find.byKey(const Key('graph-add-node')));
      await tester.pump();

      // Many small moves, like a real drag: a single big jump is eaten by the drag
      // slop, which would make the node move by less than the gesture did.
      Future<double> dragNode() async {
        final before = nodeLeft(tester, 'say0');
        final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const Key('graph-node-say0'))),
        );
        await tester.pump();
        for (var i = 0; i < 12; i++) {
          await gesture.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        await gesture.up();
        await tester.pump();
        return nodeLeft(tester, 'say0') - before;
      }

      final at100 = await dragNode();
      expect(
        at100,
        greaterThan(30),
        reason: 'the node actually moved with the pointer',
      );

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const Key('graph-zoom-in')));
      }
      await tester.pump();
      final zoomed = zoomOf(tester);
      expect(zoomed, greaterThan(2));
      final atZoom = await dragNode();
      // 120 screen px of pointer travel is 120/zoom canvas units (Flutter hands the
      // node its delta in local coordinates), less the drag slop, which Flutter also
      // measures in those units (36). So zoomed in, the same gesture moves the node
      // proportionally less - and never more than at 100%.
      expect(atZoom, lessThan(at100 / 2));
      expect(atZoom, closeTo(120 / zoomed - 36, 6));
    });

    testWidgets(
      'fit shrinks the view to show every node; it never magnifies past 100%',
      (tester) async {
        await openScreen(tester);
        await tester.tap(find.byKey(const Key('graph-zoom-fit')));
        await tester.pump();
        expect(zoomOf(tester), 1, reason: 'an empty graph resets');

        for (var i = 0; i < 6; i++) {
          await tester.tap(find.byKey(const Key('graph-add-node')));
          await tester.pump();
        }
        await tester.tap(find.byKey(const Key('graph-zoom-fit')));
        await tester.pump();
        expect(zoomOf(tester), lessThanOrEqualTo(1));
        expect(zoomOf(tester), greaterThanOrEqualTo(0.25));
      },
    );

    testWidgets('connecting ports still works after zooming', (tester) async {
      await openScreen(tester);
      await tester.tap(find.byKey(const Key('graph-add-node')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('graph-add-node')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('graph-zoom-out')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('graph-port-say0-out-out')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('graph-port-say1-in-in')));
      await tester.pump();
      expect(find.byKey(const Key('graph-port-error')), findsNothing);
      expect(
        find.textContaining('not reachable'),
        findsNothing,
        reason: 'the edge exists',
      );
    });
  });
}
