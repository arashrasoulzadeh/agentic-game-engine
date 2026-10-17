import 'dart:ui' show FrameTiming;

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Action, Text, Velocity;
import 'package:flutter/material.dart' as m show Text;
import 'package:flutter_test/flutter_test.dart';

FrameTiming _timing({required int buildUs, required int rasterUs}) {
  // vsyncStart, buildStart, buildFinish, rasterStart, rasterFinish, rasterFinishWall
  final b = buildUs, r = rasterUs;
  return FrameTiming(
    vsyncStart: 0,
    buildStart: 0,
    buildFinish: b,
    rasterStart: b,
    rasterFinish: b + r,
    rasterFinishWallTime: b + r,
  );
}

World _world() {
  final w = World(width: 100, height: 100);
  registerCoreComponents(w);
  registerFlutterComponents(w);
  return w;
}

void main() {
  group('FrameStats history', () {
    test('recordHistory keeps the latest frame and step times, capped', () {
      final s = FrameStats();
      for (var i = 0; i < FrameStats.historyLength + 10; i++) {
        s
          ..frameMs = i.toDouble()
          ..stepMs = i / 10
          ..recordHistory();
      }
      expect(s.frameHistory.length, FrameStats.historyLength);
      expect(s.frameHistory.last, FrameStats.historyLength + 9);
      expect(s.stepHistory.last, (FrameStats.historyLength + 9) / 10);
    });
  });

  group('FrameTimingMonitor', () {
    test(
      'splits build from raster time, counts jank and remembers the worst',
      () {
        final m = FrameTimingMonitor();
        final jank = <double>[];
        m.onJank = jank.add;
        m.record([
          _timing(buildUs: 2000, rasterUs: 4000),
          _timing(buildUs: 1000, rasterUs: 30000),
          _timing(buildUs: 1000, rasterUs: 5000),
        ]);
        expect(m.frames, 3);
        expect(m.jankFrames, 1);
        expect(m.jankRatio, closeTo(1 / 3, 1e-9));
        expect(m.worstRasterMs, 30);
        expect(jank.single, 30);
        expect(m.lastBuildMs, 1);
        expect(m.lastRasterMs, 5);
        expect(m.rasterHistory.toList(), [4, 30, 5]);
        m.reset();
        expect(m.frames, 0);
        expect(m.jankRatio, 0);
        expect(m.rasterHistory.isEmpty, isTrue);
      },
    );

    test('attach and detach are idempotent', () {
      TestWidgetsFlutterBinding.ensureInitialized();
      final m = FrameTimingMonitor()
        ..attach()
        ..attach();
      m.detach();
      m.detach();
    });
  });

  group('DebugGraphPainter', () {
    test('scales to the budget doubled, or to a spike above it', () {
      expect(DebugGraphPainter(values: [5, 10], budget: 16).scaleMax, 32);
      expect(DebugGraphPainter(values: [5, 100], budget: 16).scaleMax, 100);
      expect(DebugGraphPainter(values: [3, 7]).scaleMax, 7);
      expect(DebugGraphPainter(values: const []).scaleMax, 1);
    });
  });

  group('widgets', () {
    testWidgets('DebugGraph shows the latest and peak values', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DebugGraph(label: 'frame', values: [4, 20, 8], budget: 16.7),
          ),
        ),
      );
      expect(find.text('frame  8.0ms  (peak 20.0)'), findsOneWidget);
      expect(find.byKey(const Key('debug-graph-canvas')), findsOneWidget);
    });

    testWidgets('EntityInspector shows components and walks entities', (
      tester,
    ) async {
      final w = _world();
      final a = w.spawn();
      final b = w.spawn();
      w.storeOf<Position>().set(a, Position(1, 2));
      w.storeOf<Velocity>().set(b, Velocity(3, 4));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntityInspector(world: w, initial: a),
          ),
        ),
      );
      expect(find.byKey(const Key('inspector-title')), findsOneWidget);
      expect(
        tester.widget<m.Text>(find.byKey(const Key('inspector-body'))).data,
        contains('"position"'),
      );

      await tester.tap(find.byKey(const Key('inspector-next')));
      await tester.pump();
      expect(
        tester.widget<m.Text>(find.byKey(const Key('inspector-title'))).data,
        contains('entity: $b'),
      );
      expect(
        tester.widget<m.Text>(find.byKey(const Key('inspector-body'))).data,
        contains('"velocity"'),
      );

      await tester.tap(find.byKey(const Key('inspector-next')));
      await tester.pump();
      expect(
        tester.widget<m.Text>(find.byKey(const Key('inspector-title'))).data,
        contains('entity: $a'),
      );
    });

    test('describe handles dead and component-less entities', () {
      final w = _world();
      final e = w.spawn();
      expect(
        EntityInspector.describeEntity(w, e),
        contains('no registered components'),
      );
      w.destroy(e);
      expect(EntityInspector.describeEntity(w, e), contains('not alive'));
    });

    testWidgets(
      'ProfilerPanel explains how to enable itself, then lists systems',
      (tester) async {
        final w = _world();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ProfilerPanel(world: w)),
          ),
        );
        expect(
          find.textContaining('world.profiler = WorldProfiler()'),
          findsOneWidget,
        );

        w.profiler = WorldProfiler();
        w.addSystem(MovementSystem());
        w.step(0.1);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ProfilerPanel(world: w)),
          ),
        );
        expect(find.textContaining('movement'), findsWidgets);
      },
    );

    testWidgets('DebugOverlay composes graphs, the census and aliased input', (
      tester,
    ) async {
      final w = _world();
      w.spawn();
      final e = w.spawn();
      w.storeOf<Position>().set(e, Position(0, 0));
      final stats = FrameStats()
        ..frameMs = 12
        ..recordHistory();
      final input = InputController(
        aliases: ActionAliases({'action_0': 'Jump'}),
      );
      input.setAction('action_0', true);
      final timings = FrameTimingMonitor()
        ..record([_timing(buildUs: 1000, rasterUs: 20000)]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DebugOverlay(
              world: w,
              frameStats: stats,
              timings: timings,
              input: input,
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('debug-overlay')), findsOneWidget);
      expect(find.byType(DebugGraph), findsWidgets);
      expect(
        tester.widget<m.Text>(find.byKey(const Key('debug-input'))).data,
        'input: Jump',
      );
      expect(
        tester.widget<m.Text>(find.byKey(const Key('debug-census'))).data,
        contains('position 1'),
      );
      expect(
        tester.widget<m.Text>(find.byKey(const Key('debug-jank'))).data,
        contains('jank 100.0%'),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'DebugOverlay refreshes on its timer and cancels it on dispose',
      (tester) async {
        final w = _world();
        final stats = FrameStats();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DebugOverlay(
                world: w,
                frameStats: stats,
                refresh: const Duration(milliseconds: 50),
              ),
            ),
          ),
        );
        stats
          ..entities = 7
          ..frameMs = 9
          ..recordHistory();
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.textContaining('entities 7'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );

    test('pressedLabel and census formatting', () {
      final input = InputController();
      expect(DebugOverlay.pressedLabel(input), 'input: -');
      input.setAction('left', true);
      input.setAction('jump', true);
      expect(DebugOverlay.pressedLabel(input), 'input: Jump, Left');
      final w = _world();
      for (var i = 0; i < 3; i++) {
        w.storeOf<Position>().set(w.spawn(), Position(0, 0));
      }
      w.storeOf<Velocity>().set(w.spawn(), Velocity(0, 0));
      expect(DebugOverlay.census(w), 'position 3, velocity 1');
    });
  });
}
