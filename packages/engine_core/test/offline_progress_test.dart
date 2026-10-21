import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

BigNumber n(String s) => BigNumber.parse(s);

final t0 = DateTime.utc(2026, 1, 1, 12);

void main() {
  group('creditFor', () {
    test('credits the time away, up to the cap', () {
      final c = OfflineProgress.creditFor(
        lastActiveAt: t0,
        now: t0.add(const Duration(hours: 3)),
      );
      expect(c.away, const Duration(hours: 3));
      expect(c.credited, const Duration(hours: 3));
      expect(c.capped, isFalse);

      final long = OfflineProgress.creditFor(
        lastActiveAt: t0,
        now: t0.add(const Duration(days: 2)),
      );
      expect(long.away, const Duration(days: 2));
      expect(long.credited, const Duration(hours: 8), reason: 'default cap');
      expect(long.capped, isTrue);
    });

    test('a short absence earns nothing', () {
      final c = OfflineProgress.creditFor(
        lastActiveAt: t0,
        now: t0.add(const Duration(seconds: 10)),
      );
      expect(c.isNone, isTrue);
      expect(c.away, const Duration(seconds: 10));
    });

    test('a clock that moved backwards grants nothing', () {
      final c = OfflineProgress.creditFor(
        lastActiveAt: t0,
        now: t0.subtract(const Duration(hours: 5)),
      );
      expect(c.isNone, isTrue);
      expect(c.away, Duration.zero, reason: 'never negative');
    });

    test('cap and minimum are configurable', () {
      const cfg = OfflineConfig(
        cap: Duration(hours: 1),
        minimumAway: Duration(minutes: 5),
      );
      expect(
        OfflineProgress.creditFor(
          lastActiveAt: t0,
          now: t0.add(const Duration(minutes: 4)),
          config: cfg,
        ).isNone,
        isTrue,
      );
      final c = OfflineProgress.creditFor(
        lastActiveAt: t0,
        now: t0.add(const Duration(hours: 2)),
        config: cfg,
      );
      expect(c.credited, const Duration(hours: 1));
    });
  });

  group('catchUp', () {
    BigTreasury economy() => BigTreasury(
      amounts: {'gold': n('100')},
      incomePerSecond: {'gold': n('2'), 'gems': n('0.001')},
    );

    test('six hours away equals six hours of online income, in one call', () {
      final offline = economy();
      final summary = OfflineProgress.catchUp(
        offline,
        lastActiveAt: t0,
        now: t0.add(const Duration(hours: 6)),
      );

      final online = economy();
      for (var i = 0; i < 6 * 3600; i++) {
        online.accrue(1);
      }
      expect(offline.of('gold').approxEquals(online.of('gold')), isTrue);
      expect(offline.of('gems').approxEquals(online.of('gems')), isTrue);
      expect(summary.gained['gold']!.approxEquals(n('43200')), isTrue);
      expect(summary.gained['gems']!.approxEquals(n('21.6')), isTrue);
      expect(summary.credit.capped, isFalse);
    });

    test('beyond the cap only the cap is paid', () {
      final t = economy();
      final summary = OfflineProgress.catchUp(
        t,
        lastActiveAt: t0,
        now: t0.add(const Duration(days: 30)),
      );
      expect(summary.credit.capped, isTrue);
      expect(
        summary.gained['gold']!.approxEquals(n('57600')),
        isTrue,
        reason: '8 h x 2/s',
      );
    });

    test('efficiency scales what is earned away', () {
      final t = economy();
      final summary = OfflineProgress.catchUp(
        t,
        lastActiveAt: t0,
        now: t0.add(const Duration(hours: 1)),
        config: const OfflineConfig(efficiency: 0.5),
      );
      expect(
        summary.gained['gold']!.approxEquals(n('3600')),
        isTrue,
        reason: '2/s x 3600 s x 0.5',
      );
    });

    test(
      'nothing is earned (and the summary is empty) for no credit or zero efficiency',
      () {
        final t = economy();
        final none = OfflineProgress.catchUp(
          t,
          lastActiveAt: t0,
          now: t0.subtract(const Duration(hours: 1)),
        );
        expect(none.isEmpty, isTrue);
        expect(t.of('gold'), n('100'));

        final zero = OfflineProgress.catchUp(
          t,
          lastActiveAt: t0,
          now: t0.add(const Duration(hours: 1)),
          config: const OfflineConfig(efficiency: 0),
        );
        expect(zero.isEmpty, isTrue);
        expect(t.of('gold'), n('100'));
      },
    );

    test('works at idle-game scale: 1e250/s for 8 h', () {
      final t = BigTreasury(incomePerSecond: {'coins': n('1e250')});
      final s = OfflineProgress.catchUp(
        t,
        lastActiveAt: t0,
        now: t0.add(const Duration(hours: 9)),
      );
      expect(s.gained['coins']!.approxEquals(n('2.88e254')), isTrue);
    });

    test('is deterministic: the same inputs give the same result', () {
      OfflineSummary run() => OfflineProgress.catchUp(
        economy(),
        lastActiveAt: t0,
        now: t0.add(const Duration(minutes: 417)),
      );
      expect(run().gained['gold'], run().gained['gold']);
    });
  });

  group('untilCap', () {
    test('counts down from when the player left, never negative', () {
      expect(
        OfflineProgress.untilCap(leftAt: t0, now: t0),
        const Duration(hours: 8),
      );
      expect(
        OfflineProgress.untilCap(
          leftAt: t0,
          now: t0.add(const Duration(hours: 3)),
        ),
        const Duration(hours: 5),
      );
      expect(
        OfflineProgress.untilCap(
          leftAt: t0,
          now: t0.add(const Duration(hours: 20)),
        ),
        Duration.zero,
      );
    });
  });
}
