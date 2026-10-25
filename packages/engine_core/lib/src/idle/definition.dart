import '../../engine_core.dart';

import 'auto_buyer.dart';
import 'challenges.dart';
import 'components.dart';
import 'golden_events.dart';
import 'progression.dart';
import 'register_components.dart';
import 'research.dart';
import 'season_pass.dart';
import 'time_warp.dart';

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
      if (type != 'table') {
        number(cost['base'], '$p.cost.base', positive: true);
      }
      if (type == 'table') {
        final prices = cost['prices'];
        if (prices is! List || prices.isEmpty) {
          errors.add('$p.cost.prices must be a non-empty list');
        } else {
          for (var j = 0; j < prices.length; j++) {
            number(prices[j], '$p.cost.prices[$j]', positive: true);
          }
        }
        final tail = cost['tailGrowth'];
        if (tail != null && (tail is! num || tail < 1)) {
          errors.add('$p.cost.tailGrowth must be a number >= 1');
        }
      } else if (type == 'geometric') {
        final growth = cost['growth'];
        if (growth is! num || growth < 1) {
          errors.add('$p.cost.growth must be a number >= 1');
        }
      } else if (type == 'linear') {
        number(cost['step'], '$p.cost.step', nonNegative: true);
      } else {
        errors.add(
          '$p.cost.type "$type" is unknown (use geometric, linear or table)',
        );
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
    final costResource = g['costResource'] as String? ?? 'coins';
    if (resources.isNotEmpty && !resources.contains(costResource)) {
      errors.add('$p.costResource "$costResource" is not a declared resource');
    }
    final requires = g['requires'];
    if (requires != null && requires is! List) {
      errors.add('$p.requires must be a list');
    } else if (requires is List) {
      for (var j = 0; j < requires.length; j++) {
        if (requires[j] is! String || (requires[j] as String).isEmpty) {
          errors.add('$p.requires[$j] must be a non-empty string');
        }
      }
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
    final hasMult = u.containsKey('multiplier');
    final hasBonus = u.containsKey('bonusPerOwned');
    if (!hasMult && !hasBonus) {
      errors.add('$p needs multiplier and/or bonusPerOwned');
    }
    if (hasMult) number(u['multiplier'], '$p.multiplier', positive: true);
    if (hasBonus) {
      number(u['bonusPerOwned'], '$p.bonusPerOwned', positive: true);
      final syn = u['synergyOf'];
      if (syn is! String || syn.isEmpty) {
        errors.add('$p.synergyOf is required when bonusPerOwned is set');
      } else if (!generatorIds.contains(syn)) {
        errors.add('$p.synergyOf "$syn" is not a generator id');
      }
    }
    final target = u['target'] ?? 'all';
    if (target != 'all' && !generatorIds.contains(target)) {
      errors.add('$p.target "$target" is not a generator id');
    }
    final cost = u['cost'];
    if (cost is Map) {
      for (final e in cost.entries) {
        number(e.value, '$p.cost.${e.key}', nonNegative: true);
        if (resources.isNotEmpty && !resources.contains(e.key)) {
          errors.add('$p.cost.${e.key} is not a declared resource');
        }
      }
    }
    final requires = u['requires'];
    if (requires != null && requires is! List) {
      errors.add('$p.requires must be a list');
    } else if (requires is List) {
      for (var j = 0; j < requires.length; j++) {
        if (requires[j] is! String || (requires[j] as String).isEmpty) {
          errors.add('$p.requires[$j] must be a non-empty string');
        }
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
        'event',
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

  final prestigeIds = <String>{};
  void checkPrestige(Object? pr, String path) {
    if (pr is! Map) {
      errors.add('$path must be an object');
      return;
    }
    if (pr['currency'] is! String) {
      errors.add('$path.currency is required');
    } else if (resources.isNotEmpty &&
        !resources.contains(pr['currency'] as String)) {
      errors.add(
        '$path.currency "${pr['currency']}" is not a declared resource',
      );
    }
    if (pr['basedOn'] is! String) {
      errors.add('$path.basedOn is required');
    } else if (resources.isNotEmpty &&
        !resources.contains(pr['basedOn'] as String)) {
      errors.add(
        '$path.basedOn "${pr['basedOn']}" is not a declared resource',
      );
    }
    final id = pr['id'] ?? 'prestige';
    if (id is! String || id.isEmpty) {
      errors.add('$path.id must be a non-empty string');
    } else if (!prestigeIds.add(id)) {
      errors.add('$path.id "$id" is used twice');
    }
    number(pr['divisor'], '$path.divisor', positive: true);
    final keep = pr['keepGenerators'];
    if (keep != null && keep is! List) {
      errors.add('$path.keepGenerators must be a list');
    } else if (keep is List) {
      for (var i = 0; i < keep.length; i++) {
        if (!generatorIds.contains(keep[i])) {
          errors.add(
            '$path.keepGenerators[$i] "${keep[i]}" is not a generator id',
          );
        }
      }
    }
    final resets = pr['resetsCurrencies'];
    if (resets != null &&
        (resets is! List || resets.any((c) => c is! String))) {
      errors.add('$path.resetsCurrencies must be a list of currency names');
    }
    final ex = pr['exponent'];
    if (ex != null && (ex is! num || ex <= 0)) {
      errors.add('$path.exponent must be greater than 0');
    }
  }

  if (json['prestige'] != null) checkPrestige(json['prestige'], 'prestige');
  final layers = json['prestiges'];
  if (layers != null && layers is! List) {
    errors.add('prestiges must be a list');
  } else if (layers is List) {
    for (var i = 0; i < layers.length; i++) {
      checkPrestige(layers[i], 'prestiges[$i]');
    }
  }
  final challengeIds = <String>{};
  final challenges = list('challenges');
  for (var i = 0; i < challenges.length; i++) {
    final c = challenges[i];
    final p = 'challenges[$i]';
    final id = c['id'];
    if (id is! String || id.isEmpty) {
      errors.add('$p.id is required');
    } else if (!challengeIds.add(id)) {
      errors.add('$p.id "$id" is used twice');
    }
    if (c['goalStat'] is! String) errors.add('$p.goalStat is required');
    number(c['goalAtLeast'], '$p.goalAtLeast');
    if (c['reward'] != null) number(c['reward'], '$p.reward', positive: true);
    final rules = c['rules'];
    if (rules != null && rules is! List) {
      errors.add('$p.rules must be a list');
    } else if (rules is List) {
      for (var j = 0; j < rules.length; j++) {
        final r = rules[j];
        final ok =
            r == 'noUpgrades' ||
            (r is String &&
                r.startsWith('noGenerator:') &&
                generatorIds.contains(r.substring(12))) ||
            (r is String &&
                r.startsWith('incomeMultiplier:') &&
                (double.tryParse(r.substring(17)) ?? 0) > 0);
        if (!ok) {
          errors.add(
            '$p.rules[$j] "$r" is not a rule (noUpgrades, noGenerator:<id>, incomeMultiplier:<number>)',
          );
        }
      }
    }
  }

  final golden = json['golden'];
  if (golden != null) {
    if (golden is! Map) {
      errors.add('golden must be an object');
    } else {
      for (final f in ['meanInterval', 'lifetime']) {
        final v = golden[f];
        if (v is! num || v <= 0)
          errors.add('golden.$f must be a number greater than 0');
      }
      final rewards = golden['rewards'];
      if (rewards is! List || rewards.isEmpty) {
        errors.add('golden.rewards must be a non-empty list');
      } else {
        for (var i = 0; i < rewards.length; i++) {
          final r = rewards[i];
          final p = 'golden.rewards[$i]';
          if (r is! Map) {
            errors.add('$p must be an object');
            continue;
          }
          if (r['kind'] != 'boost' && r['kind'] != 'payout') {
            errors.add('$p.kind must be "boost" or "payout"');
          }
          final sec = r['seconds'];
          if (sec is! num || sec <= 0)
            errors.add('$p.seconds must be a number greater than 0');
          if (r['kind'] == 'boost')
            number(r['multiplier'], '$p.multiplier', positive: true);
          final w = r['weight'];
          if (w != null && (w is! num || w <= 0))
            errors.add('$p.weight must be greater than 0');
        }
      }
    }
  }

  final ab = json['autoBuyer'];
  if (ab != null) {
    if (ab is! Map) {
      errors.add('autoBuyer must be an object');
    } else {
      final every = ab['intervalSeconds'];
      if (every != null && (every is! num || every <= 0)) {
        errors.add('autoBuyer.intervalSeconds must be greater than 0');
      }
      final per = ab['maxPerRun'];
      if (per != null && (per is! int || per < 1)) {
        errors.add('autoBuyer.maxPerRun must be a whole number >= 1');
      }
      final main = ab['mainResource'];
      if (main != null &&
          (main is! String ||
              (resources.isNotEmpty && !resources.contains(main)))) {
        errors.add('autoBuyer.mainResource must be a declared resource');
      }
    }
  }

  final researchIds = <String>{};
  final research = list('research');
  for (var i = 0; i < research.length; i++) {
    final r = research[i];
    final p = 'research[$i]';
    final id = r['id'];
    if (id is! String || id.isEmpty) {
      errors.add('$p.id is required');
    } else if (!researchIds.add(id)) {
      errors.add('$p.id "$id" is used twice');
    }
    final cost = r['cost'];
    if (cost != null && cost is! Map) {
      errors.add('$p.cost must be an object');
    } else if (cost is Map) {
      for (final e in cost.entries) {
        number(e.value, '$p.cost.${e.key}', nonNegative: true);
        if (resources.isNotEmpty && !resources.contains(e.key)) {
          errors.add('$p.cost.${e.key} is not a declared resource');
        }
      }
    }
    final unlocks = r['unlocks'];
    if (unlocks != null && unlocks is! List) {
      errors.add('$p.unlocks must be a list');
    } else if (unlocks is List) {
      for (var j = 0; j < unlocks.length; j++) {
        if (unlocks[j] is! String || (unlocks[j] as String).isEmpty) {
          errors.add('$p.unlocks[$j] must be a non-empty string');
        }
      }
    }
    final req = r['requires'];
    if (req != null && req is! List) {
      errors.add('$p.requires must be a list');
    } else if (req is List) {
      for (var j = 0; j < req.length; j++) {
        if (req[j] is! String || (req[j] as String).isEmpty) {
          errors.add('$p.requires[$j] must be a non-empty string');
        }
      }
    }
  }

  final warps = list('timeWarps');
  for (var i = 0; i < warps.length; i++) {
    final w = warps[i];
    final p = 'timeWarps[$i]';
    final id = w['id'];
    if (id is! String || id.isEmpty) {
      errors.add('$p.id is required');
    }
    final sec = w['seconds'];
    if (sec is! num || sec <= 0) {
      errors.add('$p.seconds must be a number greater than 0');
    }
    final cost = w['cost'];
    if (cost != null && cost is! Map) {
      errors.add('$p.cost must be an object');
    } else if (cost is Map) {
      for (final e in cost.entries) {
        number(e.value, '$p.cost.${e.key}', nonNegative: true);
        if (resources.isNotEmpty && !resources.contains(e.key)) {
          errors.add('$p.cost.${e.key} is not a declared resource');
        }
      }
    }
  }

  final season = json['seasonPass'];
  if (season != null) {
    if (season is! Map) {
      errors.add('seasonPass must be an object');
    } else {
      final id = season['id'];
      if (id is! String || id.isEmpty) {
        errors.add('seasonPass.id is required');
      }
      final xp = season['xpStat'];
      if (xp is! String || xp.isEmpty) {
        errors.add('seasonPass.xpStat is required');
      }
      final tiers = season['tiers'];
      if (tiers is! List || tiers.isEmpty) {
        errors.add('seasonPass.tiers must be a non-empty list');
      } else {
        for (var i = 0; i < tiers.length; i++) {
          final t = tiers[i];
          final p = 'seasonPass.tiers[$i]';
          if (t is! Map) {
            errors.add('$p must be an object');
            continue;
          }
          number(t['at'], '$p.at', positive: true);
          final grant = t['grant'];
          if (grant != null && grant is! Map) {
            errors.add('$p.grant must be an object');
          } else if (grant is Map) {
            for (final e in grant.entries) {
              number(e.value, '$p.grant.${e.key}', nonNegative: true);
              if (resources.isNotEmpty && !resources.contains(e.key)) {
                errors.add('$p.grant.${e.key} is not a declared resource');
              }
            }
          }
          if (t['multiplier'] != null) {
            number(t['multiplier'], '$p.multiplier', positive: true);
          }
          final tech = t['tech'];
          if (tech != null && (tech is! String || tech.isEmpty)) {
            errors.add('$p.tech must be a non-empty string');
          }
        }
      }
    }
  }

  final offline = json['offline'];
  if (offline != null) {
    if (offline is! Map) {
      errors.add('offline must be an object');
    } else {
      final cap = offline['capHours'];
      if (cap != null && (cap is! num || cap <= 0)) {
        errors.add('offline.capHours must be a number greater than 0');
      }
      final eff = offline['efficiency'];
      if (eff != null && (eff is! num || eff < 0 || eff > 1)) {
        errors.add('offline.efficiency must be a number between 0 and 1');
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
  for (final rule in [
    if (json['prestige'] is Map) json['prestige'],
    for (final r in (json['prestiges'] as List? ?? const [])) r,
  ]) {
    world.storeOf<PrestigeRule>().set(
      world.spawn(),
      PrestigeRule.fromJson((rule as Map).cast<String, dynamic>()),
    );
  }
  for (final c in (json['challenges'] as List? ?? const [])) {
    world.storeOf<Challenge>().set(
      world.spawn(),
      Challenge.fromJson((c as Map).cast<String, dynamic>()),
    );
  }
  if (json['golden'] is Map) {
    world.storeOf<GoldenEvents>().set(
      world.spawn(),
      GoldenEvents.fromJson((json['golden'] as Map).cast<String, dynamic>()),
    );
  }
  if (json['autoBuyer'] is Map) {
    world.storeOf<AutoBuyer>().set(
      world.spawn(),
      AutoBuyer.fromJson((json['autoBuyer'] as Map).cast<String, dynamic>()),
    );
  }
  for (final r in (json['research'] as List? ?? const [])) {
    world.storeOf<ResearchNode>().set(
      world.spawn(),
      ResearchNode.fromJson((r as Map).cast<String, dynamic>()),
    );
  }
  for (final w in (json['timeWarps'] as List? ?? const [])) {
    world.storeOf<TimeWarpOffer>().set(
      world.spawn(),
      TimeWarpOffer.fromJson((w as Map).cast<String, dynamic>()),
    );
  }
  if (json['seasonPass'] is Map) {
    world.storeOf<SeasonPass>().set(
      world.spawn(),
      SeasonPass.fromJson(
        (json['seasonPass'] as Map).cast<String, dynamic>(),
      ),
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
