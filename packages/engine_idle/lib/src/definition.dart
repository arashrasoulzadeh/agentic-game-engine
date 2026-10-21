import 'package:engine_core/engine_core.dart';

import 'components.dart';
import 'progression.dart';
import 'register_components.dart';

/// A whole idle game described as data: resources, generators, upgrades, achievements, prestige. One JSON
/// file a designer (or an agent) can edit without touching Dart.
///
/// ```json
/// {
///   "resources": { "coins": { "start": "10" } },
///   "generators": [
///     { "id": "cursor", "name": "Cursor", "cost": { "type": "geometric", "base": "15", "growth": 1.15 },
///       "output": { "coins": "0.1" }, "milestones": [ { "owned": 25, "multiplier": "2" } ] }
///   ],
///   "upgrades": [ { "id": "x2", "target": "cursor", "multiplier": "2", "cost": { "coins": "100" } } ],
///   "achievements": [ { "id": "rich", "stat": "lifetime:coins", "atLeast": "1000", "reward": "1.1" } ],
///   "prestige": { "currency": "gems", "basedOn": "coins", "divisor": "1e6" }
/// }
/// ```
///
/// [validateIdleDefinition] returns every problem with the path to it; [loadIdleDefinition] builds the
/// entities.
List<String> validateIdleDefinition(Map<String, dynamic> json) {
  final errors = <String>[];

  void number(
    Object? v,
    String path, {
    bool positive = false,
    bool nonNegative = false,
  }) {
    try {
      final b = BigNumber.fromJson(
        v ?? (throw const FormatException('missing')),
      );
      if (positive && b <= BigNumber.zero) {
        errors.add('$path must be greater than 0');
      }
      if (nonNegative && b.isNegative) {
        errors.add('$path must not be negative');
      }
    } on Object {
      errors.add('$path is not a number');
    }
  }

  List<Map<String, dynamic>> list(String key) {
    final raw = json[key];
    if (raw == null) return const [];
    if (raw is! List) {
      errors.add('$key must be a list');
      return const [];
    }
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] is Map) {
        out.add((raw[i] as Map).cast<String, dynamic>());
      } else {
        errors.add('$key[$i] must be an object');
      }
    }
    return out;
  }

  final resources = <String>{};
  final res = json['resources'];
  if (res != null && res is! Map) {
    errors.add('resources must be an object');
  }
  if (res is Map) {
    for (final e in res.entries) {
      resources.add(e.key as String);
      if (e.value is Map && (e.value as Map).containsKey('start')) {
        number(
          (e.value as Map)['start'],
          'resources.${e.key}.start',
          nonNegative: true,
        );
      }
    }
  }

  final generatorIds = <String>{};
  final gens = list('generators');
  for (var i = 0; i < gens.length; i++) {
    final g = gens[i];
    final p = 'generators[$i]';
    final id = g['id'];
    if (id is! String || id.isEmpty) {
      errors.add('$p.id is required');
    } else if (!generatorIds.add(id)) {
      errors.add('$p.id "$id" is used twice');
    }
    final cost = g['cost'];
    if (cost is! Map) {
      errors.add('$p.cost is required');
    } else {
      final type = cost['type'];
      number(cost['base'], '$p.cost.base', positive: true);
      if (type == 'geometric') {
        final growth = cost['growth'];
        if (growth is! num || growth < 1) {
          errors.add('$p.cost.growth must be a number >= 1');
        }
      } else if (type == 'linear') {
        number(cost['step'], '$p.cost.step', nonNegative: true);
      } else {
        errors.add('$p.cost.type "$type" is unknown (use geometric or linear)');
      }
    }
    final out = g['output'];
    if (out is Map) {
      for (final e in out.entries) {
        number(e.value, '$p.output.${e.key}', nonNegative: true);
        if (resources.isNotEmpty && !resources.contains(e.key)) {
          errors.add('$p.output.${e.key} is not a declared resource');
        }
      }
    } else if (out != null) {
      errors.add('$p.output must be an object');
    }
    final ms = g['milestones'];
    if (ms != null && ms is! List) {
      errors.add('$p.milestones must be a list');
    } else if (ms is List) {
      for (var j = 0; j < ms.length; j++) {
        final m = ms[j];
        if (m is! Map) {
          errors.add('$p.milestones[$j] must be an object');
          continue;
        }
        final at = m['owned'];
        if (at is! int || at < 1) {
          errors.add('$p.milestones[$j].owned must be a whole number >= 1');
        }
        number(m['multiplier'], '$p.milestones[$j].multiplier', positive: true);
      }
    }
    final max = g['maxOwned'];
    if (max != null && (max is! int || max < 1)) {
      errors.add('$p.maxOwned must be a whole number >= 1');
    }
  }

  final upgradeIds = <String>{};
  final ups = list('upgrades');
  for (var i = 0; i < ups.length; i++) {
    final u = ups[i];
    final p = 'upgrades[$i]';
    final id = u['id'];
    if (id is! String || id.isEmpty) {
      errors.add('$p.id is required');
    } else if (!upgradeIds.add(id)) {
      errors.add('$p.id "$id" is used twice');
    }
    number(u['multiplier'], '$p.multiplier', positive: true);
    final target = u['target'] ?? 'all';
    if (target != 'all' && !generatorIds.contains(target)) {
      errors.add('$p.target "$target" is not a generator id');
    }
    final cost = u['cost'];
    if (cost is Map) {
      for (final e in cost.entries) {
        number(e.value, '$p.cost.${e.key}', nonNegative: true);
      }
    }
  }

  final achievementIds = <String>{};
  final achs = list('achievements');
  for (var i = 0; i < achs.length; i++) {
    final a = achs[i];
    final p = 'achievements[$i]';
    final id = a['id'];
    if (id is! String || id.isEmpty) {
      errors.add('$p.id is required');
    } else if (!achievementIds.add(id)) {
      errors.add('$p.id "$id" is used twice');
    }
    final stat = a['stat'];
    if (stat is! String) {
      errors.add('$p.stat is required');
    } else {
      final kind = stat.split(':').first;
      const kinds = {
        'lifetime',
        'run',
        'owned',
        'prestiges',
        'taps',
        'seconds',
      };
      if (!kinds.contains(kind)) {
        errors.add('$p.stat "$stat" is unknown (use ${kinds.join(', ')})');
      } else if (kind == 'owned' &&
          !generatorIds.contains(stat.substring(stat.indexOf(':') + 1))) {
        errors.add('$p.stat "$stat" names an unknown generator');
      }
    }
    number(a['atLeast'], '$p.atLeast');
    if (a['reward'] != null) number(a['reward'], '$p.reward', positive: true);
  }

  final pr = json['prestige'];
  if (pr != null) {
    if (pr is! Map) {
      errors.add('prestige must be an object');
    } else {
      if (pr['currency'] is! String) {
        errors.add('prestige.currency is required');
      }
      if (pr['basedOn'] is! String) {
        errors.add('prestige.basedOn is required');
      }
      number(pr['divisor'], 'prestige.divisor', positive: true);
      final ex = pr['exponent'];
      if (ex != null && (ex is! num || ex <= 0)) {
        errors.add('prestige.exponent must be greater than 0');
      }
    }
  }
  return errors;
}

/// Thrown by [loadIdleDefinition] with every problem found.
class IdleDefinitionException implements Exception {
  final List<String> problems;
  IdleDefinitionException(this.problems);

  @override
  String toString() => 'IdleDefinitionException:\n  ${problems.join('\n  ')}';
}

/// What [loadIdleDefinition] created.
class IdleGame {
  IdleGame(this.wallet, this.offline);

  /// The game's resources.
  final BigTreasury wallet;

  /// The offline-progress rules from the definition (`offline.capHours`, `offline.efficiency`).
  final OfflineConfig offline;
}

/// Registers the idle components on [world] and fills it from [json]: a wallet with the starting
/// resources, an [IdleStats], an [IdleModifiers], and one entity per generator, upgrade and achievement
/// plus the prestige rule. Throws [IdleDefinitionException] listing every problem if the definition is
/// not valid; nothing is created in that case.
IdleGame loadIdleDefinition(World world, Map<String, dynamic> json) {
  final problems = validateIdleDefinition(json);
  if (problems.isNotEmpty) throw IdleDefinitionException(problems);

  registerIdleComponents(world);
  final amounts = <String, BigNumber>{};
  for (final e in ((json['resources'] as Map?) ?? const {}).entries) {
    final start = e.value is Map ? (e.value as Map)['start'] : null;
    amounts[e.key as String] = start == null
        ? BigNumber.zero
        : BigNumber.fromJson(start as Object);
  }
  final wallet = BigTreasury(amounts: amounts);
  world.storeOf<BigTreasury>().set(world.spawn(), wallet);
  world.storeOf<IdleStats>().set(world.spawn(), IdleStats());
  world.storeOf<IdleModifiers>().set(world.spawn(), IdleModifiers());

  for (final g in (json['generators'] as List? ?? const [])) {
    world.storeOf<Generator>().set(
      world.spawn(),
      Generator.fromJson((g as Map).cast<String, dynamic>()),
    );
  }
  for (final u in (json['upgrades'] as List? ?? const [])) {
    world.storeOf<Upgrade>().set(
      world.spawn(),
      Upgrade.fromJson((u as Map).cast<String, dynamic>()),
    );
  }
  for (final a in (json['achievements'] as List? ?? const [])) {
    world.storeOf<Achievement>().set(
      world.spawn(),
      Achievement.fromJson((a as Map).cast<String, dynamic>()),
    );
  }
  if (json['prestige'] is Map) {
    world.storeOf<PrestigeRule>().set(
      world.spawn(),
      PrestigeRule.fromJson((json['prestige'] as Map).cast<String, dynamic>()),
    );
  }

  final off = json['offline'] is Map
      ? (json['offline'] as Map).cast<String, dynamic>()
      : const {};
  return IdleGame(
    wallet,
    OfflineConfig(
      cap: Duration(minutes: (((off['capHours'] as num?) ?? 8) * 60).round()),
      efficiency: ((off['efficiency'] as num?) ?? 1).toDouble(),
    ),
  );
}
