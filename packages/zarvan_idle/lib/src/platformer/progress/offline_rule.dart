import 'hero_progress.dart';

/// How much a wave-combat hero earns while the app is closed: the auto-fighter
/// keeps killing at a fixed rate, discounted, up to a cap.
class OfflineRule {
  const OfflineRule({
    this.coinsPerMinute = 6,
    this.perWaveGrowth = 0.15,
    this.efficiency = 0.5,
    this.capHours = 8,
    this.minAway = const Duration(minutes: 1),
  });

  /// Coins per minute at wave 0, and the fractional rise per best wave.
  final double coinsPerMinute;
  final double perWaveGrowth;

  /// Share of the live rate earned away (0..1).
  final double efficiency;

  /// Longest span that counts.
  final int capHours;

  /// Shorter absences earn nothing and show no message.
  final Duration minAway;

  /// Coins for [away] given [progress] (whole coins, 0 under [minAway]).
  int coins(HeroProgress progress, Duration away) {
    if (away < minAway) return 0;
    final counted = away > Duration(hours: capHours)
        ? Duration(hours: capHours)
        : away;
    final rate =
        coinsPerMinute *
        (1 + perWaveGrowth * progress.bestWave) *
        (1 + 0.1 * progress.stars);
    return (counted.inSeconds / 60 * rate * efficiency).floor();
  }
}
