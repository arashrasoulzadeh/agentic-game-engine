import 'package:engine_core/engine_core.dart';

import 'fighter_anims.dart';

/// Who is fighting (hero lane vs enemy lane).
class CombatRole {
  CombatRole(this.side);
  final String side; // 'hero' | 'enemy'

  Map<String, dynamic> toJson() => {'side': side};
  factory CombatRole.fromJson(Map<String, dynamic> json) =>
      CombatRole(json['side'] as String);
}

/// Mobarez combat stats + attack timer (portrait idle auto-fight).
class CombatStats {
  CombatStats({
    required this.maxHp,
    required this.attack,
    required this.attackSpeed,
    required this.armor,
    this.cooldown = 0,
  });

  final double maxHp;
  final double attack;
  final double attackSpeed;
  final double armor;
  double cooldown;

  Map<String, dynamic> toJson() => {
    'maxHp': maxHp,
    'attack': attack,
    'attackSpeed': attackSpeed,
    'armor': armor,
    'cooldown': cooldown,
  };

  factory CombatStats.fromJson(Map<String, dynamic> json) => CombatStats(
    maxHp: (json['maxHp'] as num).toDouble(),
    attack: (json['attack'] as num).toDouble(),
    attackSpeed: (json['attackSpeed'] as num).toDouble(),
    armor: (json['armor'] as num).toDouble(),
    cooldown: (json['cooldown'] as num?)?.toDouble() ?? 0,
  );
}

void registerCombatComponents(World world) {
  if (world.components.isRegistered('combatRole')) return;
  world.components.register<FighterAnims>(
    'fighterAnims',
    (c) => c.toJson(),
    FighterAnims.fromJson,
  );
  world.components.register<CombatRole>(
    'combatRole',
    (c) => c.toJson(),
    CombatRole.fromJson,
  );
  world.components.register<CombatStats>(
    'combatStats',
    (c) => c.toJson(),
    CombatStats.fromJson,
  );
}
