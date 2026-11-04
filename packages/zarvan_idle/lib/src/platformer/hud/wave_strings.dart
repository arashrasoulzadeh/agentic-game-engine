import '../progress/gear.dart';

/// Every word a wave-combat scene draws itself, so a game can translate or
/// reword it (pass your own to `WaveCombatConfig.strings`). Enemy names and
/// descriptions come from the fighters' own data, not from here.
class WaveStrings {
  const WaveStrings({
    this.coins = 'Coins',
    this.max = 'MAX',
    this.retry = 'Retry',
    this.ascend = 'Ascend',
    this.dodge = 'Dodge',
    this.combo = 'Combo',
    this.elite = 'Elite',
    this.golden = 'Golden',
    this.loot = 'Loot',
    this.ready = 'READY',
    this.wave = 'Wave',
    this.kills = 'Kills',
    this.best = 'Best',
    this.stars = 'Stars',
    this.coinsWhileAway = 'coins earned while away',
    this.hintUpgrade = 'Spend coins on upgrades to grow stronger',
    this.hintSkill = 'Tap a skill when it is ready',
  });

  final String coins;
  final String max;
  final String retry;
  final String ascend;
  final String dodge;
  final String combo;
  final String elite;
  final String golden;
  final String loot;
  final String ready;
  final String wave;
  final String kills;
  final String best;
  final String stars;
  final String coinsWhileAway;
  final String hintUpgrade;
  final String hintSkill;

  String coinsLabel(int n) => '$coins $n';
  String comboLabel(int n) => '$combo x$n';
  String eliteName(String name) => '$elite $name';
  String goldenName(String name) => '$golden $name';

  /// The retry button text; names the wave a checkpoint restarts at.
  String retryLabel(int startWave) =>
      startWave > 1 ? '$retry ($wave $startWave)' : retry;

  String awayMessage(int coinsEarned) => '+$coinsEarned $coinsWhileAway';

  /// The one-line summary under a finished run.
  String summary({
    required int wave,
    required int killCount,
    required int bestWave,
  }) => '${this.wave} $wave · $kills $killCount · $best ${bestWave + 1}';

  String lootLabel(Gear gear) =>
      '$loot: ${gear.name} +${(gear.bonus * 100).round()}%';

  /// A short "what am I wearing" line.
  String gearSummary(Iterable<Gear> worn) =>
      worn.map((g) => '${g.name} +${(g.bonus * 100).round()}%').join(' · ');
}
