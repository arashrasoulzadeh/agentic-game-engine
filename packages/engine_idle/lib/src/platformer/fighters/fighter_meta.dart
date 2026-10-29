import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'package:engine_flutter/engine_flutter.dart';

import '../level/level_data.dart' show StateCues;

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

/// A fighter's display [name], [stats] and one sheet per animation state
/// (`idle`, `attack`, `death`), parsed once so callers don't re-read the
/// same JSON assets. Sheets are `<stemPrefix>_<state>.png/.json`.
class FighterMeta {
  const FighterMeta({
    required this.id,
    required this.name,
    required this.stats,
    required this.stemPrefix,
    required this.frames,
    this.descriptionFa = '',
  });

  /// States every fighter is expected to ship a sheet for.
  static const states = ['idle', 'attack', 'death'];

  final String id;
  final String name;
  final MobarezStats stats;
  final String stemPrefix;

  /// Persian lore line from the sidecar (`history_fa`), empty if absent.
  final String descriptionFa;

  /// Frame count per state, from each sheet's own sidecar.
  final Map<String, int> frames;

  /// Asset stem (no extension) of [state]'s sheet.
  String stem(String state) => '${stemPrefix}_$state';

  /// Atlas id under which [state]'s sheet is registered.
  String atlasId(String state) => '${id}_$state';

  /// Non-idle states as [SpriteClip]s for [spawnFighter]'s `extraClips`,
  /// with each state's [cues] attached to the frames they name.
  Map<String, SpriteClip> extraClips({StateCues cues = const {}}) => {
    for (final e in frames.entries)
      if (e.key != 'idle')
        e.key: SpriteClip(
          atlasId: atlasId(e.key),
          frames: e.value,
          frameSeconds: e.key == 'death' ? 0.18 : 0.1,
          frameEvents: cues[e.key] == null
              ? null
              : [for (var i = 0; i < e.value; i++) cues[e.key]![i] ?? const []],
        ),
  };

  static Future<FighterMeta> load(String id, String stemPrefix) async {
    Future<Map<String, dynamic>> read(String state) async =>
        jsonDecode(await rootBundle.loadString('${stemPrefix}_$state.json'))
            as Map<String, dynamic>;

    final idle = await read('idle');
    final frames = <String, int>{
      'idle': (idle['frames'] as num?)?.toInt() ?? 4,
    };
    for (final state in states.skip(1)) {
      frames[state] = ((await read(state))['frames'] as num?)?.toInt() ?? 1;
    }
    return FighterMeta(
      id: id,
      name: idle['name'] as String? ?? id,
      stats: MobarezStats.fromJson(idle),
      stemPrefix: stemPrefix,
      frames: frames,
      descriptionFa: idle['history_fa'] as String? ?? '',
    );
  }
}
