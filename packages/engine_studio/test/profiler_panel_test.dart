import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/preview/preview_view.dart';
import 'package:engine_studio/src/preview/profiler_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LevelDocument _level() => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'player',
      'components': {
        'position': {'x': 8.0, 'y': 8.0},
      },
    },
  ],
});

void main() {
  testWidgets(
    'shows the step cost, entity count and the slowest systems first',
    (tester) async {
      final p = WorldProfiler()
        ..recordSystem('gravity', 0.2)
        ..recordSystem('collision', 1.5)
        ..recordSystem('input', 0.05)
        ..recordStep(stepMs: 2.0, eventsMs: 0.1, entities: 42)
        ..recordStep(stepMs: 3.0, eventsMs: 0.1, entities: 42);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfilerPanel(profiler: p, rows: 2)),
        ),
      );

      expect(find.text('step 3.00 ms · 42 entities'), findsOneWidget);
      expect(find.byKey(const Key('profiler-row-collision')), findsOneWidget);
      expect(find.byKey(const Key('profiler-row-gravity')), findsOneWidget);
      expect(
        find.byKey(const Key('profiler-row-input')),
        findsNothing,
        reason: 'only the slowest `rows`',
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('profiler-row-collision'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('profiler-row-gravity'))).dy,
        ),
      );
    },
  );

  testWidgets('says so when nothing has been timed yet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProfilerPanel(profiler: WorldProfiler())),
      ),
    );
    expect(find.byKey(const Key('profiler-empty')), findsOneWidget);
  });

  testWidgets(
    'the preview hides the panel until the Profiler switch is on, then shows real timings',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PreviewView(document: _level(), running: true)),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('profiler-panel')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('profiler-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('profiler-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('profiler-panel')), findsOneWidget);
      expect(
        find.byKey(const Key('profiler-empty')),
        findsNothing,
        reason: 'the preview timed its systems',
      );
      expect(find.textContaining(' entities'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const Key('profiler-paint')),
        findsOneWidget,
        reason: 'the preview timed its own painting',
      );
    },
  );

  test('PaintTimer keeps the last paint and smooths the average', () {
    final t = PaintTimer();
    expect(t.frames, 0);
    t.record(10);
    expect((t.lastMs, t.averageMs), (10, 10));
    t.record(20);
    expect(t.lastMs, 20);
    expect(t.averageMs, closeTo(12, 1e-9), reason: '10*0.8 + 20*0.2');
    expect(t.frames, 2);
  });

  testWidgets('the paint line appears only when a timer with data is given', (
    tester,
  ) async {
    final p = WorldProfiler()..recordStep(stepMs: 1, eventsMs: 0, entities: 1);
    Future<void> show(PaintTimer? t) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfilerPanel(profiler: p, paintTimer: t),
        ),
      ),
    );
    await show(null);
    expect(find.byKey(const Key('profiler-paint')), findsNothing);
    await show(PaintTimer());
    expect(find.byKey(const Key('profiler-paint')), findsNothing);
    await show(PaintTimer()..record(3.5));
    expect(find.text('paint 3.50 ms (avg 3.50)'), findsOneWidget);
  });
}
