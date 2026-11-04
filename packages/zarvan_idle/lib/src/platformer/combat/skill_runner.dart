import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart' show Health;

import '../progress/hero_skill.dart';
import 'auto_combat_system.dart';
import 'combat_components.dart';

/// Runs the hero's [HeroSkill]s: cooldowns, and the effect of each use. A
/// guard lasts while [guardLeft] counts down and cuts the enemy's damage
/// through the combat system's modifiers.
class SkillRunner {
  SkillRunner(this.skills, AutoCombatSystem combat)
    : cooldowns = SkillCooldowns(skills) {
    combat.damageModifiers.add(
      (side) => side == 'enemy' && guardLeft > 0 ? 1 - _guardPower : 1,
    );
  }

  final List<HeroSkill> skills;
  final SkillCooldowns cooldowns;

  /// Seconds of guard left (0 = none).
  double guardLeft = 0;
  double _guardPower = 0;

  void tick(double dt) {
    cooldowns.tick(dt);
    if (guardLeft > 0) guardLeft = (guardLeft - dt).clamp(0, double.infinity);
  }

  /// Uses [skill] if it is ready and its target exists; true when it fired.
  bool use(
    World world,
    HeroSkill skill, {
    required EntityId hero,
    required EntityId? enemy,
  }) {
    if (!cooldowns.ready(skill)) return false;
    final health = world.componentsOf<Health>();
    final heroHp = health.get(hero);
    if (heroHp == null || heroHp.current <= 0) return false;
    switch (skill.kind) {
      case SkillKind.strike:
        final enemyHp = enemy == null ? null : health.get(enemy);
        final stats = world.componentsOf<CombatStats>();
        if (enemy == null || enemyHp == null || enemyHp.current <= 0) {
          return false;
        }
        final raw =
            stats.get(hero)!.attack * skill.power - stats.get(enemy)!.armor;
        final damage = raw < 1 ? 1.0 : raw;
        enemyHp.current = (enemyHp.current - damage).clamp(0, enemyHp.max);
        world.events.emit(
          FighterHit(
            attacker: hero,
            defender: enemy,
            attackerSide: 'hero',
            damage: damage,
            fatal: enemyHp.current <= 0,
            critical: true,
          ),
        );
      case SkillKind.heal:
        heroHp.current = (heroHp.current + heroHp.max * skill.power).clamp(
          0,
          heroHp.max,
        );
      case SkillKind.guard:
        guardLeft = skill.duration;
        _guardPower = skill.power.clamp(0.0, 1.0);
    }
    cooldowns.use(skill);
    return true;
  }
}
