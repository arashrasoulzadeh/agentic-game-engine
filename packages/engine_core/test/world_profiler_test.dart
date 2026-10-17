import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Busy extends System {
  _Busy(this.name, this.spinMs);
  @override
  final String name;
  final int spinMs;
  int runs = 0;
  @override
  void update(World world, double dt) {
    runs++;
    final sw = Stopwatch()..start();
    while (sw.elapsedMilliseconds < spinMs) {}
  }
}

void main() {
  test('RingBuffer keeps the newest values oldest-first and wraps', () {
    final r = RingBuffer<int>(3);
    expect(r.isEmpty, isTrue);
    expect(r.last, isNull);
    for (var i = 1; i <= 5; i++) {
      r.add(i);
    }
    expect(r.toList(), [3, 4, 5]);
    expect(r.length, 3);
    expect(r.last, 5);
    r.clear();
    expect(r.toList(), isEmpty);
    r.add(9);
    expect(r.toList(), [9]);
  });

  test('without a profiler step still runs every system', () {
    final w = World(width: 1, height: 1);
    final a = _Busy('a', 0);
    w.addSystem(a);
    w.step(0.1);
    expect(a.runs, 1);
    expect(w.profiler, isNull);
  });

  test('profiling times each system, ranks the slow one first, and keeps history', () {
    final w = World(width: 1, height: 1);
    w.profiler = WorldProfiler();
    w.addSystem(_Busy('fast', 0));
    w.addSystem(_Busy('slow', 4));
    for (var i = 0; i < 3; i++) {
      w.step(0.1);
    }
    final p = w.profiler!;
    expect(p.steps, 3);
    final report = p.report();
    expect(report.first.name, 'slow');
    expect(report.first.averageMs, greaterThanOrEqualTo(3.5));
    expect(report.last.name, 'fast');
    expect(report.first.samples, 3);
    expect(p.stepMs, greaterThanOrEqualTo(report.first.lastMs));
    expect(p.stepHistory.length, 3);
    expect(p.shares()['slow']!, greaterThan(p.shares()['fast']!));
    expect(w.tick, 3);
  });

  test('the average smooths and max remembers the worst step', () {
    final p = WorldProfiler(smoothing: 0.5);
    p.recordSystem('s', 10);
    p.recordSystem('s', 0);
    final t = p.report().single;
    expect(t.averageMs, 5);
    expect(t.maxMs, 10);
    expect(t.lastMs, 0);
  });

  test('reset clears everything; JSON and the table list each system', () {
    final w = World(width: 1, height: 1);
    w.profiler = WorldProfiler();
    w.addSystem(_Busy('only', 0));
    w.step(0.1);
    final json = w.profiler!.toJson();
    expect((json['systems'] as List).single['name'], 'only');
    expect(json['steps'], 1);
    expect(w.profiler!.format(), contains('only'));
    w.profiler!.reset();
    expect(w.profiler!.report(), isEmpty);
    expect(w.profiler!.steps, 0);
    expect(w.profiler!.shares(), isEmpty);
  });

  test('events flushed during a step are timed and entity count is recorded', () {
    final w = World(width: 1, height: 1);
    w.profiler = WorldProfiler();
    w.spawn();
    w.spawn();
    w.step(0.1);
    expect(w.profiler!.entityCount, 2);
    expect(w.profiler!.eventsMs, greaterThanOrEqualTo(0));
  });

  test('componentCounts is a census that omits empty stores', () {
    final w = World(width: 1, height: 1);
    registerCoreComponents(w);
    final a = w.spawn();
    final b = w.spawn();
    w.storeOf<Position>().set(a, Position(0, 0));
    w.storeOf<Position>().set(b, Position(1, 1));
    w.storeOf<Velocity>().set(a, Velocity(0, 0));
    final counts = w.componentCounts();
    expect(counts['position'], 2);
    expect(counts['velocity'], 1);
    expect(counts.containsKey('collider'), isFalse);
  });

  test('invalid configuration is rejected', () {
    expect(() => WorldProfiler(smoothing: 0), throwsA(isA<AssertionError>()));
    expect(() => RingBuffer<int>(0), throwsA(isA<AssertionError>()));
  });
}
