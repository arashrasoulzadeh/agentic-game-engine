// ignore_for_file: avoid_print
// Hot paths of an idle game: recomputing income with many generators, asking how many a budget buys, and
// a long offline catch-up.
//
//   dart run benchmark/idle_bench.dart
//
// Host baseline (macOS Apple Silicon, 2026-10-25): recomputeIncome≈312 us/op,
// geometric maxAffordable≈1.5 us, offline catch-up≈0.8 us, formatBigNumber≈0.5 us.
// Real-device (release APK) confirmation is still open in TODO.md — phone CPUs can
// differ; re-run this script on-device via a Flutter isolate or compare against
// test/performance_budget_test.dart's loose CI ceilings.
import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';

BigNumber n(String s) => BigNumber.parse(s);

void time(String label, int iterations, void Function() body) {
  body();
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  sw.stop();
  final perUs = sw.elapsedMicroseconds / iterations;
  print('${label.padRight(44)} ${perUs.toStringAsFixed(1).padLeft(10)} us/op');
}

void main() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerIdleComponents(w);
  final wallet = BigTreasury(amounts: {'coins': n('1e30')});
  w.storeOf<BigTreasury>().set(w.spawn(), wallet);
  w.storeOf<IdleModifiers>().set(w.spawn(), IdleModifiers());
  w.storeOf<IdleStats>().set(w.spawn(), IdleStats());
  for (var i = 0; i < 1000; i++) {
    w.storeOf<Generator>().set(
      w.spawn(),
      Generator(
        id: 'g$i',
        owned: 50,
        cost: GeometricCost(base: n('10'), growth: 1.15),
        output: {'coins': n('1.5')},
        milestones: [Milestone(25, n('2')), Milestone(100, n('3'))],
      ),
    );
  }
  recomputeIncome(w, wallet);

  time(
    'recomputeIncome, 1000 generators',
    200,
    () => recomputeIncome(w, wallet),
  );
  final curve = GeometricCost(base: n('15'), growth: 1.15);
  time(
    'maxAffordable, geometric, 1e30 budget',
    20000,
    () => curve.maxAffordable(10, n('1e30')),
  );
  final table = TableCost(
    prices: [for (var i = 1; i <= 50; i++) n('${i * 10}')],
    tailGrowth: 1.2,
  );
  time(
    'maxAffordable, table + tail, 1e30 budget',
    5000,
    () => table.maxAffordable(0, n('1e30')),
  );
  final t0 = DateTime.utc(2026);
  time('offline catch-up, 6 months', 20000, () {
    OfflineProgress.catchUp(
      wallet,
      lastActiveAt: t0,
      now: t0.add(const Duration(days: 182)),
      config: const OfflineConfig(cap: Duration(days: 365)),
    );
  });
  time('formatBigNumber', 100000, () => formatBigNumber(n('1.2345e87')));
}
