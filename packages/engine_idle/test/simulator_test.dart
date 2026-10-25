import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> cookie() =>
    jsonDecode(File('example/cookie_clicker.json').readAsStringSync())
        as Map<String, dynamic>;

({World world, IdleGame game}) load(Map<String, dynamic> json) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  return (world: w, game: loadIdleDefinition(w, json));
}

SimulationReport run(
  Map<String, dynamic> json, {
  Duration limit = const Duration(days: 1),
  double? prestigeAt,
  bool playChallenges = true,
}) {
  final g = load(json);
  return simulateIdle(
    g.world,
    g.game.wallet,
    limit: limit,
    prestigeAt: prestigeAt,
    playChallenges: playChallenges,
  );
}

void main() {
  test('the sample game validates and is playable', () {
    expect(validateIdleDefinition(cookie()), isEmpty);
  });

  test(
    'a day of greedy play grows income by orders of magnitude and records milestones',
    () {
      final r = run(cookie());
      expect(r.purchases, greaterThan(20));
      expect(r.finalIncome['coins']! > BigNumber.from(100), isTrue);
      expect(
        r.milestones.map((m) => m.label),
        contains('income reaches 1e1 coins/s'),
      );
      expect(
        r.milestones
            .map((m) => m.label)
            .any((l) => l.startsWith('achievement:')),
        isTrue,
      );
      expect(r.stalled, isFalse);
      expect(r.elapsed <= const Duration(days: 1), isTrue);
    },
  );

  test('milestones are in order and never later than the time covered', () {
    final r = run(cookie());
    for (var i = 1; i < r.milestones.length; i++) {
      expect(r.milestones[i].at >= r.milestones[i - 1].at, isTrue);
    }
    expect(
      r.milestones.last.at <= r.elapsed + const Duration(seconds: 1),
      isTrue,
    );
  });

  test('it is deterministic: the same definition gives the same report', () {
    String sig(SimulationReport r) =>
        '${r.purchases}|${r.elapsed}|${r.finalIncome['coins']}|${r.milestones.map((m) => '${m.at}:${m.label}').join(',')}';
    expect(sig(run(cookie())), sig(run(cookie())));
  });

  test('a longer run reaches at least as far', () {
    final short = run(cookie(), limit: const Duration(hours: 6));
    final long = run(cookie(), limit: const Duration(days: 2));
    expect(long.finalIncome['coins']! >= short.finalIncome['coins']!, isTrue);
  });

  test('prestige-at makes it prestige and reset when worthwhile', () {
    final r = run(cookie(), limit: const Duration(days: 3), prestigeAt: 1.0);
    expect(r.milestones.any((m) => m.label.startsWith('prestige #')), isTrue);
  });

  test(
    'prestige-at considers every layer: a ready higher layer fires instead of only the first',
    () {
      final layered = cookie()
        ..['resources'] = {
          'coins': {'start': '15'},
          'gems': <String, dynamic>{},
          'stars': <String, dynamic>{},
        }
        ..remove('prestige')
        ..['prestiges'] = [
          {
            'id': 'prestige',
            'currency': 'gems',
            'basedOn': 'coins',
            'divisor': '1e6',
            'exponent': 0.5,
            'bonusPerUnit': 0.05,
            'startingAmounts': {'coins': '15'},
          },
          {
            'id': 'ascend',
            'currency': 'stars',
            'basedOn': 'gems',
            'divisor': '10',
            'exponent': 1,
            'bonusPerUnit': 0.5,
            'resetsCurrencies': ['gems'],
            'startingAmounts': {'coins': '15'},
          },
        ];
      final r = run(
        layered,
        limit: const Duration(days: 14),
        prestigeAt: 1.0,
      );
      expect(
        r.milestones.any((m) => m.label.startsWith('prestige #')),
        isTrue,
        reason: 'first layer still prestiges',
      );
      expect(
        r.milestones.any((m) => m.label.startsWith('prestige ascend #')),
        isTrue,
        reason: 'higher layer is not ignored',
      );
    },
  );

  test(
    'it starts and completes challenges, and playChallenges: false skips them',
    () {
      final withChallenge = cookie()
        ..['challenges'] = [
          {
            'id': 'frugal',
            'rules': ['noUpgrades'],
            'goalStat': 'run:coins',
            'goalAtLeast': '50',
            'reward': '2',
          },
        ];
      final played = run(
        withChallenge,
        limit: const Duration(hours: 6),
        playChallenges: true,
      );
      expect(
        played.milestones.map((m) => m.label),
        containsAll(['challenge start: frugal', 'challenge completed: frugal']),
      );

      final skipped = run(
        withChallenge,
        limit: const Duration(hours: 6),
        playChallenges: false,
      );
      expect(
        skipped.milestones.any((m) => m.label.contains('challenge')),
        isFalse,
      );
    },
  );

  test(
    'a design with nothing that earns anything stalls instead of looping forever',
    () {
      final dead = {
        'resources': {
          'coins': {'start': '5'},
        },
        'generators': [
          {
            'id': 'g',
            'cost': {'type': 'geometric', 'base': '10', 'growth': 1.1},
            'output': <String, dynamic>{},
          },
        ],
      };
      final r = run(dead);
      expect(r.stalled, isTrue);
      expect(r.purchases, 0);
    },
  );

  test('an unaffordable first purchase with no income stalls', () {
    final poor = {
      'resources': {
        'coins': {'start': '1'},
      },
      'generators': [
        {
          'id': 'g',
          'cost': {'type': 'geometric', 'base': '100', 'growth': 1.1},
          'output': {'coins': '1'},
        },
      ],
    };
    final r = run(poor);
    expect(r.stalled, isTrue);
    expect(r.stallReason, isNotNull);
  });
}
