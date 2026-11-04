import 'package:zarvan_core/zarvan_core.dart';

import 'conditions.dart';
import 'enemy_powers.dart';

/// Who is fighting (hero lane vs enemy lane).
class CombatRole {
  CombatRole(this.side);
  final String side; // 'hero' | 'enemy'

  Map<String, dynamic> toJson() => {'side': side};
  factory CombatRole.fromJson(Map<String, dynamic> json) =>
      CombatRole(json['side'] as String);
}

/// Combat stats + attack timer for portrait idle auto-fight.
class CombatStats {
  CombatStats({
    required this.maxHp,
    required this.attack,
    required this.attackSpeed,
    required this.armor,
    this.cooldown = 0,
    this.critChance = 0,
    this.critMultiplier = 1.5,
  });

  final double maxHp;
  final double attack;
  final double attackSpeed;
  final double armor;
  double cooldown;

  /// Chance (0..1) that a hit is critical and deals [critMultiplier] damage.
  final double critChance;
  final double critMultiplier;

  /// A copy with the given fields changed. Stats are immutable so a change
  /// (an upgrade) is a new value; copying here means a field added later cannot
  /// be dropped by whoever rebuilds one by hand.
  CombatStats copyWith({
    double? maxHp,
    double? attack,
    double? attackSpeed,
    double? armor,
    double? cooldown,
    double? critChance,
    double? critMultiplier,
  }) => CombatStats(
    maxHp: maxHp ?? this.maxHp,
    attack: attack ?? this.attack,
    attackSpeed: attackSpeed ?? this.attackSpeed,
    armor: armor ?? this.armor,
    cooldown: cooldown ?? this.cooldown,
    critChance: critChance ?? this.critChance,
    critMultiplier: critMultiplier ?? this.critMultiplier,
  );

  Map<String, dynamic> toJson() => {
    'maxHp': maxHp,
    'attack': attack,
    'attackSpeed': attackSpeed,
    'armor': armor,
    'cooldown': cooldown,
    'critChance': critChance,
    'critMultiplier': critMultiplier,
  };

  factory CombatStats.fromJson(Map<String, dynamic> json) => CombatStats(
    maxHp: (json['maxHp'] as num).toDouble(),
    attack: (json['attack'] as num).toDouble(),
    attackSpeed: (json['attackSpeed'] as num).toDouble(),
    armor: (json['armor'] as num).toDouble(),
    cooldown: (json['cooldown'] as num?)?.toDouble() ?? 0,
    critChance: (json['critChance'] as num?)?.toDouble() ?? 0,
    critMultiplier: (json['critMultiplier'] as num?)?.toDouble() ?? 1.5,
  );
}

void registerCombatComponents(World world) {
  registerConditionComponents(world);
  if (world.components.isRegistered('combatRole')) return;
  world.components.register<CombatRole>(
    'combatRole',
    (c) => c.toJson(),
    CombatRole.fromJson,
  );
  world.components.register<EnemyPowers>(
    'enemyPowers',
    (c) => c.toJson(),
    EnemyPowers.fromJson,
  );
  world.components.register<CombatStats>(
    'combatStats',
    (c) => c.toJson(),
    CombatStats.fromJson,
  );
}

/// Emitted by `AutoCombatSystem` for every landed hit, so presentation
/// (effects, sound, damage numbers) can react without touching combat.
class FighterHit {
  FighterHit({
    required this.attacker,
    required this.defender,
    required this.attackerSide,
    required this.damage,
    required this.fatal,
    this.critical = false,
  });

  final EntityId attacker;
  final EntityId defender;
  final String attackerSide;
  final double damage;

  /// The hit took the defender's health to zero.
  final bool fatal;

  /// The hit rolled a critical (already included in [damage]).
  final bool critical;
}

/// A fighter avoided a hit entirely (its `EnemyPowers.dodge`).
class FighterDodge {
  FighterDodge({required this.attacker, required this.defender});

  final EntityId attacker;
  final EntityId defender;
}

/// A fighter is about to attack in [seconds]: presentation can telegraph it.
class AttackWindup {
  AttackWindup({
    required this.attacker,
    required this.attackerSide,
    required this.seconds,
  });

  final EntityId attacker;
  final String attackerSide;
  final double seconds;
}
