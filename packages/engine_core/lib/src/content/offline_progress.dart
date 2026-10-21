import 'big_number.dart';
import 'big_treasury.dart';

/// Rules for turning time away into progress.
class OfflineConfig {
  /// The most away time that counts. An idle game's cap is a design lever (and the reason a
  /// reminder is worth sending), not a limit of the maths.
  final Duration cap;

  /// Fraction of normal income earned while away: `1` is full, `0.5` half. Idle games often pay
  /// less offline than online.
  final double efficiency;

  /// Absences shorter than this earn nothing and show no summary (switching apps for a moment is not
  /// "being away").
  final Duration minimumAway;

  const OfflineConfig({
    this.cap = const Duration(hours: 8),
    this.efficiency = 1.0,
    this.minimumAway = const Duration(seconds: 30),
  }) : assert(efficiency >= 0, 'efficiency must not be negative');
}

/// How much of an absence counts.
class OfflineCredit {
  const OfflineCredit({
    required this.away,
    required this.credited,
    required this.capped,
  });

  /// The real time that passed (never negative).
  final Duration away;

  /// The time that earns income: [away] clamped to the cap, or zero if shorter than the minimum.
  final Duration credited;

  /// Whether [away] exceeded the cap.
  final bool capped;

  /// Nothing to show or apply.
  bool get isNone => credited == Duration.zero;

  /// No credit.
  static const OfflineCredit none = OfflineCredit(
    away: Duration.zero,
    credited: Duration.zero,
    capped: false,
  );
}

/// What a catch-up earned, for the "while you were away" screen.
class OfflineSummary {
  const OfflineSummary({required this.credit, required this.gained});

  final OfflineCredit credit;

  /// Resource -> amount earned. Only resources that actually increased are listed.
  final Map<String, BigNumber> gained;

  bool get isEmpty => gained.isEmpty;
}

/// Offline progress: work out how much of an absence counts, and apply it to a [BigTreasury].
///
/// Time enters only through the `lastActiveAt` and `now` arguments - never `DateTime.now()` inside -
/// so the same inputs always give the same result and tests can pick any clock.
class OfflineProgress {
  const OfflineProgress._();

  /// How much of the time between [lastActiveAt] and [now] counts under [config].
  ///
  /// A clock that moved **backwards** (the player changed it, or travelled across a time change the
  /// device mishandled) earns nothing rather than negative or free time.
  static OfflineCredit creditFor({
    required DateTime lastActiveAt,
    required DateTime now,
    OfflineConfig config = const OfflineConfig(),
  }) {
    final away = now.difference(lastActiveAt);
    if (away.isNegative) return OfflineCredit.none;
    if (away < config.minimumAway) {
      return OfflineCredit(away: away, credited: Duration.zero, capped: false);
    }
    final capped = away > config.cap;
    return OfflineCredit(
      away: away,
      credited: capped ? config.cap : away,
      capped: capped,
    );
  }

  /// Applies [credit] to [treasury] at [config]'s efficiency and reports what was gained. One
  /// accrual of the whole credited time, not one per tick: income is rate times time, so the result
  /// equals playing that time online at the same rates, in microseconds.
  static OfflineSummary applyToTreasury(
    BigTreasury treasury,
    OfflineCredit credit, {
    OfflineConfig config = const OfflineConfig(),
  }) {
    if (credit.isNone || config.efficiency == 0) {
      return OfflineSummary(credit: credit, gained: const {});
    }
    final seconds =
        credit.credited.inMicroseconds /
        Duration.microsecondsPerSecond *
        config.efficiency;
    treasury.accrue(seconds);
    // Computed from the rates, not by comparing wallets: next to a 1e300 balance the earnings are below
    // the number's precision, and a wallet diff would report "nothing earned" for a real payout.
    final gained = <String, BigNumber>{};
    final factor = BigNumber.from(seconds);
    for (final e in treasury.incomePerSecond.entries) {
      final gain = e.value * factor;
      if (gain > BigNumber.zero) gained[e.key] = gain;
    }
    return OfflineSummary(credit: credit, gained: gained);
  }

  /// [creditFor] then [applyToTreasury], the usual call on app start / resume.
  static OfflineSummary catchUp(
    BigTreasury treasury, {
    required DateTime lastActiveAt,
    required DateTime now,
    OfflineConfig config = const OfflineConfig(),
  }) => applyToTreasury(
    treasury,
    creditFor(lastActiveAt: lastActiveAt, now: now, config: config),
    config: config,
  );

  /// How long until the cap is reached if the player leaves at [leftAt], for scheduling a "your
  /// generators are full" reminder and for UI that says so. Zero if already past it.
  static Duration untilCap({
    required DateTime leftAt,
    required DateTime now,
    OfflineConfig config = const OfflineConfig(),
  }) {
    final remaining = config.cap - now.difference(leftAt);
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
