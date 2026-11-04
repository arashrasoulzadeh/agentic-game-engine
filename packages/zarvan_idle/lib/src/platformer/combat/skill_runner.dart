import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart' show Health;

import '../progress/hero_skill.dart';
import 'auto_combat_system.dart';
import 'combat_components.dart';

/// Runs the hero's [HeroSkill]s: cooldowns, and the effect of each use. A
/// guard lasts while [guardLeft] counts down and cuts the enemy's damage
/// through the combat system's modifiers.
class SkillRunner {
  SkillRunner(this.skills, this.combat) : cooldowns = SkillCooldowns(skills) {
    combat.damageModifiers.add(
      (side) => side == 'enemy' && guardLeft > 0 ? 1 - _guardPower : 1,
    );
  }

  final List<HeroSkill> skills;
  final AutoCombatSystem combat;
  final SkillCooldowns cooldowns;

  /// Seconds of guard left (0 = none).
  double guardLeft = 0;
  double _guardPower = 0;

  void tick(double dt) {
    cooldowns.tick(dt);
    if (guardLeft > 0) guardLeft = (guardLeft - dt).clamp(0, double.infinity);
  }

  /// Uses [skill] if it is ready and its target exists; true when it fired.
  /// A skill with `hitsAll` strikes every one of [enemies] (the single [enemy]
  /// when the list is empty); an `ultimate` one also needs a full meter.
  bool use(
    World world,
    HeroSkill skill, {
    required EntityId hero,
    required EntityId? enemy,
    List<EntityId> enemies = const [],
  }) {
    if (!cooldowns.ready(skill)) return false;
    if (skill.ultimate && combat.ultimate < 1) return false;
    final health = world.componentsOf<Health>();
    final heroHp = health.get(hero);
    if (heroHp == null || heroHp.current <= 0) return false;
    switch (skill.kind) {
      case SkillKind.strike:
        final stats = world.componentsOf<CombatStats>();
        final targets = <EntityId>[
          if (skill.hitsAll && enemies.isNotEmpty) ...enemies else ?enemy,
        ].where((e) => (health.get(e)?.current ?? 0) > 0).toList();
        if (targets.isEmpty) return false;
        for (final target in targets) {
          final enemyHp = health.get(target)!;
          final raw =
              stats.get(hero)!.attack * skill.power - stats.get(target)!.armor;
          final damage = raw < 1 ? 1.0 : raw;
          enemyHp.current = (enemyHp.current - damage).clamp(0, enemyHp.max);
          world.events.emit(
            FighterHit(
              attacker: hero,
              defender: target,
              attackerSide: 'hero',
              damage: damage,
              fatal: enemyHp.current <= 0,
              critical: true,
            ),
          );
        }
      case SkillKind.heal:
        heroHp.current = (heroHp.current + heroHp.max * skill.power).clamp(
          0,
          heroHp.max,
        );
      case SkillKind.guard:
        guardLeft = skill.duration;
        _guardPower = skill.power.clamp(0.0, 1.0);
    }
    if (skill.ultimate) combat.spendUltimate();
    cooldowns.use(skill);
    return true;
  }
}
