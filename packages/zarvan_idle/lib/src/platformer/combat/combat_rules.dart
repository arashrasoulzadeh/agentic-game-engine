import '../level/wave_plan.dart';
import 'auto_combat_system.dart';

/// Rules for the player's timing in a wave-combat scene: tap during an enemy's
/// wind-up to parry it, tap just before the hero swings for a timed strike, and
/// fill an ultimate meter by doing both. Pass one to `WaveCombatConfig.timing`;
/// null (default) leaves combat fully automatic. Needs `windupSeconds` above 0 for
/// parrying, since the wind-up is the window.
class CombatTimingRules {
  const CombatTimingRules({
    this.strikeWindowSeconds = 0.25,
    this.missLockoutSeconds = 0.5,
    this.counterBonus = 1.5,
    this.counterSeconds = 2,
    this.timedStrikeMultiplier = 2,
    this.ultimateGainPerHit = 0.04,
    this.ultimateGainPerParry = 0.34,
    this.ultimateGainPerTimedStrike = 0.2,
  });

  /// A tap this long before the hero's attack makes it a timed strike.
  final double strikeWindowSeconds;

  /// A tap outside every window locks tapping for this long (anti-mashing).
  final double missLockoutSeconds;

  /// Damage multiplier for [counterSeconds] after a parry.
  final double counterBonus;
  final double counterSeconds;

  /// Damage multiplier of a timed strike (never below the hero's crit).
  final double timedStrikeMultiplier;

  /// Ultimate meter (0..1) gained per hero hit, parry and timed strike.
  final double ultimateGainPerHit;
  final double ultimateGainPerParry;
  final double ultimateGainPerTimedStrike;

  /// Copies the rules onto [combat] and switches player timing on.
  void applyTo(AutoCombatSystem combat) {
    combat
      ..playerTiming = true
      ..strikeWindowSeconds = strikeWindowSeconds
      ..missLockoutSeconds = missLockoutSeconds
      ..counterBonus = counterBonus
      ..counterSeconds = counterSeconds
      ..timedStrikeMultiplier = timedStrikeMultiplier
      ..ultimateGainPerHit = ultimateGainPerHit
      ..ultimateGainPerParry = ultimateGainPerParry
      ..ultimateGainPerTimedStrike = ultimateGainPerTimedStrike;
  }
}

/// How many enemies come at once. Pass one to `WaveCombatConfig.squad`; null
/// (default) keeps every wave a one-on-one. The extras are the wave's own enemy
/// at [extraStrength] of its health and attack, standing behind the front one
/// ([rowOffsetX], [rowOffsetY] per row, each [backScale] smaller). Bosses and
/// treasure enemies always come alone.
class SquadRule {
  const SquadRule({
    this.oneExtraFromWave = 3,
    this.twoExtrasFromWave = 8,
    this.extraStrength = 0.6,
    this.rowOffsetX = 16,
    this.rowOffsetY = -12,
    this.backScale = 0.9,
  });

  /// First wave (1-based) that has one extra enemy, and the first that has two.
  /// 0 or less means never.
  final int oneExtraFromWave;
  final int twoExtrasFromWave;

  /// Health and attack of an extra, as a fraction of the front enemy's.
  final double extraStrength;

  /// Where each further row stands, relative to the one in front, in world
  /// units, and how much smaller it is drawn.
  final double rowOffsetX;
  final double rowOffsetY;
  final double backScale;

  /// How many extra enemies [wave] (0-based index) has.
  int extrasFor(int wave, {required bool boss, required WaveKind kind}) {
    if (boss || kind == WaveKind.treasure) return 0;
    final n = wave + 1;
    if (twoExtrasFromWave > 0 && n >= twoExtrasFromWave) return 2;
    if (oneExtraFromWave > 0 && n >= oneExtraFromWave) return 1;
    return 0;
  }
}
