// The samples in docs/concepts/idle-games.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('big numbers: arithmetic past a 64-bit int, and display', () {
    final a = BigNumber.parse('1.5e300');
    final b = BigNumber.from(2000);
    expect((a * b).exponent, 303);
    expect(formatBigNumber(BigNumber.from(1234567)), '1.23M');
    expect(
      formatBigNumber(BigNumber.parse('4.5e12'), style: NumberStyle.scientific),
      '4.50e12',
    );
    expect(
      formatBigNumber(BigNumber.from(999999)),
      '1.00M',
      reason: 'rounding carries',
    );
  });

  test('a generator economy with offline catch-up', () {
    final wallet = BigTreasury(
      amounts: {'coins': BigNumber.from(10)},
      incomePerSecond: {'coins': BigNumber.from(5)},
    );

    // The player leaves at noon and comes back 3 hours later.
    final leftAt = DateTime.utc(2026, 1, 1, 12);
    final now = leftAt.add(const Duration(hours: 3));
    final summary = OfflineProgress.catchUp(
      wallet,
      lastActiveAt: leftAt,
      now: now,
    );

    expect(summary.credit.credited, const Duration(hours: 3));
    expect(
      summary.gained['coins']!.approxEquals(BigNumber.from(54000)),
      isTrue,
    );
    expect(formatBigNumber(summary.gained['coins']!), '54.00K');

    // Buying something uses spend(): all or nothing.
    expect(wallet.spend({'coins': BigNumber.from(100000)}), isFalse);
    expect(wallet.spend({'coins': BigNumber.from(50000)}), isTrue);
  });

  test('the cap, efficiency and the reminder time', () {
    const config = OfflineConfig(cap: Duration(hours: 4), efficiency: 0.5);
    final left = DateTime.utc(2026, 1, 1);
    final credit = OfflineProgress.creditFor(
      lastActiveAt: left,
      now: left.add(const Duration(days: 1)),
      config: config,
    );
    expect(credit.credited, const Duration(hours: 4));
    expect(credit.capped, isTrue);

    expect(
      OfflineProgress.untilCap(leftAt: left, now: left, config: config),
      const Duration(hours: 4),
    );
  });
}
