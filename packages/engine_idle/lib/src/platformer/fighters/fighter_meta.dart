import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Stats block shared by hero / enemy Mobarez sidecars.
class MobarezStats {
  MobarezStats({
    required this.hp,
    required this.attack,
    required this.attackSpeed,
    required this.armor,
    this.regeneration = 0,
    this.frames = 4,
    this.cell = 64,
  });

  final double hp;
  final double attack;
  final double attackSpeed;
  final double armor;
  final double regeneration;
  final int frames;
  final double cell;

  factory MobarezStats.fromJson(Map<String, dynamic> json) {
    final s = (json['stats'] as Map?)?.cast<String, dynamic>() ?? json;
    return MobarezStats(
      hp: (s['hp'] as num? ?? s['health'] as num? ?? 1).toDouble(),
      attack: (s['attack'] as num? ?? s['damage'] as num? ?? 1).toDouble(),
      attackSpeed: (s['attack_speed'] as num? ?? 1).toDouble(),
      armor: (s['armor'] as num? ?? 0).toDouble(),
      regeneration: (s['regeneration'] as num? ?? 0).toDouble(),
      frames: (json['frames'] as num?)?.toInt() ?? 4,
      cell: (json['cell'] as num?)?.toDouble() ?? 64,
    );
  }
}

/// A fighter sidecar: display [name] plus [stats], parsed once so callers
/// don't re-read the same JSON asset.
class FighterMeta {
  const FighterMeta({
    required this.id,
    required this.name,
    required this.stats,
  });

  final String id;
  final String name;
  final MobarezStats stats;

  factory FighterMeta.fromJson(String id, Map<String, dynamic> json) =>
      FighterMeta(
        id: id,
        name: json['name'] as String? ?? id,
        stats: MobarezStats.fromJson(json),
      );

  static Future<FighterMeta> load(String id, String assetStem) async =>
      FighterMeta.fromJson(
        id,
        jsonDecode(await rootBundle.loadString('$assetStem.json'))
            as Map<String, dynamic>,
      );
}
