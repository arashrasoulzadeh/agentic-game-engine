import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

/// Budgets are deliberately loose (CI machines are slow): they exist to catch an accidental O(n^2) or a
/// loop over the offline duration, not to measure speed.
void main() {
  test(
    '1000 generators: income recompute and a 6-month offline catch-up stay fast',
    () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      registerIdleComponents(w);
      final wallet = BigTreasury(amounts: {'coins': n('1000')});
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

      final recompute = Stopwatch()..start();
      for (var i = 0; i < 20; i++) {
        recomputeIncome(w, wallet);
      }
      recompute.stop();
      expect(
        recompute.elapsedMilliseconds / 20,
        lessThan(100),
        reason: 'per recompute, ms',
      );

      final t0 = DateTime.utc(2026);
      final catchUp = Stopwatch()..start();
      final summary = OfflineProgress.catchUp(
        wallet,
        lastActiveAt: t0,
        now: t0.add(const Duration(days: 182)),
        config: const OfflineConfig(cap: Duration(days: 365)),
      );
      catchUp.stop();
      expect(summary.isEmpty, isFalse);
      expect(catchUp.elapsedMilliseconds, lessThan(50));
    },
  );
}
