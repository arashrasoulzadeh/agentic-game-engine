import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart' show Health;

import '../combat/combat_components.dart';
import 'hero_progress.dart';

/// The hero's stats: the level's base values multiplied by the bought
/// upgrades. One place derives them, for spawning and for a purchase made
/// mid-fight, so the two cannot disagree.
class HeroLoadout {
  HeroLoadout({
    required this.hp,
    required this.attack,
    required this.attackSpeed,
    required this.armor,
    required this.upgrades,
    required this.progress,
    this.starBonusPerStar = 0,
  });

  /// Base stats before upgrades (the level's preview scaling already applied).
  final double hp, attack, attackSpeed, armor;
  final List<HeroUpgrade> upgrades;
  final HeroProgress progress;

  /// Permanent bonus per prestige star on hp and attack (0.1 = +10% each).
  final double starBonusPerStar;

  double get _stars => 1 + progress.stars * starBonusPerStar;

  /// Upgrades plus worn gear for [stat], as a multiplier of the base.
  double _up(String stat) =>
      progress.multiplier(stat, upgrades) + progress.gearBonus(stat);

  double get maxHp => hp * _up('hp') * _stars;
  double get attackNow => attack * _up('attack') * _stars;
  double get attackSpeedNow => attackSpeed * _up('attack_speed');
  double get armorNow => armor * _up('armor');

  /// Re-derives [hero]'s stats after a purchase, keeping its crit values and
  /// attack cooldown and the health fraction it already has.
  void apply(World world, EntityId hero) {
    final stats = world.componentsOf<CombatStats>();
    final health = world.componentsOf<Health>().get(hero);
    final old = stats.get(hero);
    if (old == null || health == null) return;
    final fraction = health.max <= 0 ? 1.0 : health.current / health.max;
    stats.set(
      hero,
      old.copyWith(
        maxHp: maxHp,
        attack: attackNow,
        attackSpeed: attackSpeedNow,
        armor: armorNow,
      ),
    );
    health
      ..max = maxHp
      ..current = maxHp * fraction;
  }
}
