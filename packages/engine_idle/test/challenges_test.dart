import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

({World world, BigTreasury wallet, EntityId cursor, EntityId up, Challenge c})
game({List<String> rules = const ['noUpgrades'], String reward = '3'}) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerIdleComponents(w);
  final wallet = BigTreasury(amounts: {'coins': n('1000')});
  w.storeOf<BigTreasury>().set(w.spawn(), wallet);
  w.storeOf<IdleModifiers>().set(w.spawn(), IdleModifiers());
  w.storeOf<IdleStats>().set(w.spawn(), IdleStats());
  final cursor = w.spawn();
  w.storeOf<Generator>().set(
    cursor,
    Generator(
      id: 'cursor',
      cost: GeometricCost(base: n('10'), growth: 1.1),
      output: {'coins': n('1')},
    ),
  );
  final up = w.spawn();
  w.storeOf<Upgrade>().set(
    up,
    Upgrade(
      id: 'x2',
      target: 'all',
      multiplier: n('2'),
      cost: {'coins': n('5')},
    ),
  );
  final c = Challenge(
    id: 'frugal',
    rules: rules,
    goalStat: 'run:coins',
    goalAtLeast: n('500'),
    reward: n(reward),
  );
  w.storeOf<Challenge>().set(w.spawn(), c);
  w.storeOf<PrestigeRule>().set(
    w.spawn(),
    PrestigeRule(
      currency: 'gems',
      basedOn: 'coins',
      divisor: n('1e6'),
      startingAmounts: {'coins': n('50')},
    ),
  );
  return (world: w, wallet: wallet, cursor: cursor, up: up, c: c);
}

void main() {
  test('starting restarts the run with the restriction in force', () {
    final g = game();
    g.world.storeOf<Generator>().get(g.cursor)!.owned = 5;
    g.world.storeOf<Upgrade>().get(g.up)!.purchased = true;
    g.wallet.add('gems', n('7'));
    expect(startChallenge(g.world, g.wallet, 'frugal'), isTrue);
    expect(g.c.active, isTrue);
    expect(g.world.storeOf<Generator>().get(g.cursor)!.owned, 0);
    expect(g.world.storeOf<Upgrade>().get(g.up)!.purchased, isFalse);
    expect(
      g.wallet.of('coins'),
      n('50'),
      reason: 'the first prestige rule\'s starting amounts',
    );
    expect(g.wallet.of('gems'), n('7'), reason: 'prestige currencies survive');
  });

  test(
    'noUpgrades refuses upgrades (and the advisor skips them); generators still work',
    () {
      final g = game();
      startChallenge(g.world, g.wallet, 'frugal');
      expect(buyUpgrade(g.world, g.wallet, g.up).failure, BuyFailure.challenge);
      expect(buyGenerator(g.world, g.wallet, g.cursor).ok, isTrue);
      final best = bestPurchase(g.world, g.wallet);
      expect(best == null || !best.isUpgrade, isTrue);
    },
  );

  test('noGenerator:<id> forbids that generator only', () {
    final g = game(rules: ['noGenerator:cursor']);
    startChallenge(g.world, g.wallet, 'frugal');
    expect(
      buyGenerator(g.world, g.wallet, g.cursor).failure,
      BuyFailure.challenge,
    );
    expect(buyUpgrade(g.world, g.wallet, g.up).ok, isTrue);
  });

  test('incomeMultiplier is a handicap that ends with the challenge', () {
    final g = game(rules: ['incomeMultiplier:0.1']);
    g.world.storeOf<Generator>().get(g.cursor)!.owned = 10;
    recomputeIncome(g.world, g.wallet);
    expect(g.wallet.rateOf('coins'), n('10'));
    startChallenge(g.world, g.wallet, 'frugal');
    buyGenerator(g.world, g.wallet, g.cursor, count: 3);
    expect(g.wallet.rateOf('coins').approxEquals(n('0.3')), isTrue);
    abandonChallenge(g.world, g.wallet);
    expect(g.wallet.rateOf('coins'), n('3'));
  });

  test(
    'reaching the goal completes it: restriction lifted, reward granted for good, event emitted',
    () {
      final g = game();
      final events = <String>[];
      g.world.events.on<ChallengeCompletedEvent>((e) => events.add(e.id));
      startChallenge(g.world, g.wallet, 'frugal');
      buyGenerator(g.world, g.wallet, g.cursor, count: 2);
      final before = g.wallet.rateOf('coins');
      g.world.storeOf<IdleStats>().denseAt(0).credit({'coins': n('499')});
      expect(checkChallenges(g.world, g.wallet), isNull, reason: 'one short');
      g.world.storeOf<IdleStats>().denseAt(0).credit({'coins': n('1')});
      expect(checkAchievements(g.world, g.wallet), isEmpty);
      expect(g.c.completed, isTrue);
      expect(g.c.active, isFalse);
      g.world.events.flush();
      expect(events, ['frugal']);
      expect(g.wallet.rateOf('coins').approxEquals(before * n('3')), isTrue);
      expect(
        buyUpgrade(g.world, g.wallet, g.up).ok,
        isTrue,
        reason: 'no longer restricted',
      );
      expect(
        startChallenge(g.world, g.wallet, 'frugal'),
        isFalse,
        reason: 'a completed challenge is done',
      );
    },
  );

  test(
    'only one challenge runs at a time, unknown ids and abandon without one are refused',
    () {
      final g = game();
      g.world.storeOf<Challenge>().set(
        g.world.spawn(),
        Challenge(id: 'other', goalStat: 'taps', goalAtLeast: n('10')),
      );
      expect(startChallenge(g.world, g.wallet, 'nope'), isFalse);
      expect(abandonChallenge(g.world, g.wallet), isFalse);
      expect(startChallenge(g.world, g.wallet, 'frugal'), isTrue);
      expect(startChallenge(g.world, g.wallet, 'other'), isFalse);
      expect(abandonChallenge(g.world, g.wallet), isTrue);
      expect(g.c.completed, isFalse);
      expect(startChallenge(g.world, g.wallet, 'other'), isTrue);
    },
  );

  test('state survives JSON', () {
    final g = game();
    startChallenge(g.world, g.wallet, 'frugal');
    final back = Challenge.fromJson(g.c.toJson());
    expect(
      (back.active, back.completed, back.goalStat),
      (true, false, 'run:coins'),
    );
    expect(back.rules, ['noUpgrades']);
    expect(back.reward, n('3'));
  });

  group('definition', () {
    Map<String, dynamic> base() => {
      'resources': {
        'coins': {'start': '15'},
      },
      'generators': [
        {
          'id': 'cursor',
          'cost': {'type': 'geometric', 'base': '15', 'growth': 1.15},
          'output': {'coins': '1'},
        },
      ],
    };

    test('a challenges list loads', () {
      final j = base()
        ..['challenges'] = [
          {
            'id': 'a',
            'rules': [
              'noUpgrades',
              'noGenerator:cursor',
              'incomeMultiplier:0.5',
            ],
            'goalStat': 'run:coins',
            'goalAtLeast': '1000',
            'reward': '2',
          },
        ];
      expect(validateIdleDefinition(j), isEmpty);
      final w = World(width: 4, height: 4);
      registerCoreComponents(w);
      loadIdleDefinition(w, j);
      expect(w.storeOf<Challenge>().denseAt(0).rules, hasLength(3));
    });

    test('bad rules and fields are reported with their path', () {
      final j = base()
        ..['challenges'] = [
          {
            'id': 'a',
            'rules': ['noGenerator:ghost', 'fly', 'incomeMultiplier:0'],
            'goalAtLeast': 'x',
          },
          {'id': 'a', 'goalStat': 'taps', 'goalAtLeast': '1'},
        ];
      expect(
        validateIdleDefinition(j),
        containsAll([
          'challenges[0].goalStat is required',
          'challenges[0].goalAtLeast is not a number',
          'challenges[0].rules[0] "noGenerator:ghost" is not a rule (noUpgrades, noGenerator:<id>, incomeMultiplier:<number>)',
          'challenges[0].rules[1] "fly" is not a rule (noUpgrades, noGenerator:<id>, incomeMultiplier:<number>)',
          'challenges[0].rules[2] "incomeMultiplier:0" is not a rule (noUpgrades, noGenerator:<id>, incomeMultiplier:<number>)',
          'challenges[1].id "a" is used twice',
        ]),
      );
    });
  });
}
