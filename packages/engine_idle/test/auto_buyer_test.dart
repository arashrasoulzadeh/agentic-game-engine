import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

({World world, BigTreasury wallet, EntityId cursor, EntityId farm, EntityId up})
game({String coins = '100'}) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerIdleComponents(w);
  final wallet = BigTreasury(amounts: {'coins': n(coins)});
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
  final farm = w.spawn();
  w.storeOf<Generator>().set(
    farm,
    Generator(
      id: 'farm',
      cost: GeometricCost(base: n('100'), growth: 1.1),
      output: {'coins': n('20')},
    ),
  );
  final up = w.spawn();
  w.storeOf<Upgrade>().set(
    up,
    Upgrade(
      id: 'x2',
      target: 'all',
      multiplier: n('2'),
      cost: {'coins': n('500')},
    ),
  );
  recomputeIncome(w, wallet);
  return (world: w, wallet: wallet, cursor: cursor, farm: farm, up: up);
}

void main() {
  group('bestPurchase', () {
    test(
      'picks the best payback: a farm at 100 (5/coin-per-s) beats a cursor at 10 (10/coin-per-s)',
      () {
        final g = game();
        final best = bestPurchase(g.world, g.wallet)!;
        expect(best.entity, g.farm);
        expect(best.isUpgrade, isFalse);
        expect(best.cost, n('100'));
      },
    );

    test(
      'affordableOnly skips what the wallet cannot pay now; the default would wait for it',
      () {
        final g = game(coins: '50');
        expect(
          bestPurchase(g.world, g.wallet, affordableOnly: true)!.entity,
          g.cursor,
        );
        g.wallet.incomePerSecond['coins'] = n('1');
        expect(
          bestPurchase(g.world, g.wallet)!.entity,
          g.farm,
          reason: 'income exists, so it can be waited for',
        );
      },
    );

    test(
      'a gem-cost upgrade is not treated as a free coin buy before prestige',
      () {
        final g = game(coins: '1e9');
        final gemUp = g.world.spawn();
        g.world.storeOf<Upgrade>().set(
          gemUp,
          Upgrade(
            id: 'gem_boost',
            target: 'all',
            multiplier: n('2'),
            cost: {'gems': n('5')},
          ),
        );
        g.wallet.incomePerSecond['coins'] = n('10');
        final best = bestPurchase(g.world, g.wallet)!;
        expect(
          best.entity,
          isNot(gemUp),
          reason: 'gems are not earned yet, so gem upgrades are ineligible',
        );
        expect(best.resource, 'coins');

        // Cap generators and buy the coin upgrade so only the gem shop remains.
        for (final e in [g.cursor, g.farm]) {
          final gen = g.world.storeOf<Generator>().get(e)!;
          g.world.storeOf<Generator>().set(
            e,
            Generator(
              id: gen.id,
              cost: gen.cost,
              output: gen.output,
              owned: gen.maxOwned ?? 3,
              maxOwned: gen.maxOwned ?? 3,
            ),
          );
        }
        g.world.storeOf<Upgrade>().get(g.up)!.purchased = true;
        expect(
          bestPurchase(g.world, g.wallet),
          isNull,
          reason: 'still no gems to spend',
        );
        g.wallet.amounts['gems'] = n('5');
        final withGems = bestPurchase(g.world, g.wallet)!;
        expect(withGems.entity, gemUp);
        expect(withGems.resource, 'gems');
        expect(withGems.cost, n('5'));
      },
    );

    test(
      'nothing affordable gives null, and so does a game with nothing left to buy',
      () {
        final g = game(coins: '1');
        expect(bestPurchase(g.world, g.wallet, affordableOnly: true), isNull);

        final capped = game(coins: '1e9');
        for (final e in [capped.cursor, capped.farm]) {
          final gen = capped.world.storeOf<Generator>().get(e)!;
          capped.world.storeOf<Generator>().set(
            e,
            Generator(
              id: gen.id,
              cost: gen.cost,
              output: gen.output,
              owned: 3,
              maxOwned: 3,
            ),
          );
        }
        capped.world.storeOf<Upgrade>().get(capped.up)!.purchased = true;
        expect(bestPurchase(capped.world, capped.wallet), isNull);
      },
    );
  });

  group('AutoBuyer', () {
    test(
      'waits for its interval, then buys what is affordable, best payback first',
      () {
        final g = game(coins: '250');
        g.world.storeOf<AutoBuyer>().set(
          g.world.spawn(),
          AutoBuyer(intervalSeconds: 5),
        );
        final sys = AutoBuySystem();
        sys.update(g.world, 4);
        expect(
          g.world.storeOf<Generator>().get(g.farm)!.owned,
          0,
          reason: 'not yet',
        );
        sys.update(g.world, 1);
        expect(g.world.storeOf<Generator>().get(g.farm)!.owned, greaterThan(0));
        expect(g.wallet.of('coins'), lessThan(n('250')));
      },
    );

    test('maxPerRun caps one pass, and runAutoBuyer reports the count', () {
      final g = game(coins: '1000000');
      final buyer = AutoBuyer(maxPerRun: 3);
      expect(runAutoBuyer(g.world, g.wallet, buyer), 3);
      expect(runAutoBuyer(g.world, g.wallet, AutoBuyer(maxPerRun: 50)), 50);
    });

    test('a disabled buyer does nothing; enabling it resumes', () {
      final g = game(coins: '1000');
      final buyer = AutoBuyer(enabled: false, intervalSeconds: 1);
      g.world.storeOf<AutoBuyer>().set(g.world.spawn(), buyer);
      final sys = AutoBuySystem();
      sys.update(g.world, 10);
      expect(g.wallet.of('coins'), n('1000'));
      buyer.enabled = true;
      sys.update(g.world, 1);
      expect(g.wallet.of('coins'), lessThan(n('1000')));
    });

    test('state round-trips through JSON and the registry', () {
      final b = AutoBuyer(
        intervalSeconds: 2.5,
        mainResource: 'gems',
        maxPerRun: 4,
        elapsed: 1.25,
        enabled: false,
      );
      final back = AutoBuyer.fromJson(b.toJson());
      expect(
        (
          back.intervalSeconds,
          back.mainResource,
          back.maxPerRun,
          back.elapsed,
          back.enabled,
        ),
        (2.5, 'gems', 4, 1.25, false),
      );
      final w = World(width: 4, height: 4);
      registerCoreComponents(w);
      registerIdleComponents(w);
      expect(w.components.isRegistered('autoBuyer'), isTrue);
    });

    test('with income and time, an automated economy outgrows an idle one', () {
      BigNumber run(bool auto) {
        final g = game(coins: '15');
        g.world
          ..addSystem(IdleSystem())
          ..addSystem(AutoBuySystem());
        if (auto) {
          g.world.storeOf<AutoBuyer>().set(
            g.world.spawn(),
            AutoBuyer(intervalSeconds: 2),
          );
        }
        for (var i = 0; i < 600; i++) {
          g.world.step(1);
        }
        return g.wallet.rateOf('coins');
      }

      expect(run(true), greaterThan(run(false)));
    });
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

    test('an autoBuyer block loads into the component', () {
      final j = base()..['autoBuyer'] = {'intervalSeconds': 3, 'maxPerRun': 2};
      expect(validateIdleDefinition(j), isEmpty);
      final w = World(width: 4, height: 4);
      registerCoreComponents(w);
      loadIdleDefinition(w, j);
      final b = w.storeOf<AutoBuyer>().denseAt(0);
      expect((b.intervalSeconds, b.maxPerRun), (3.0, 2));
    });

    test('bad values are reported with their path', () {
      expect(
        validateIdleDefinition(
          base()
            ..['autoBuyer'] = {
              'intervalSeconds': 0,
              'maxPerRun': 0,
              'mainResource': 'gold',
            },
        ),
        [
          'autoBuyer.intervalSeconds must be greater than 0',
          'autoBuyer.maxPerRun must be a whole number >= 1',
          'autoBuyer.mainResource must be a declared resource',
        ],
      );
      expect(validateIdleDefinition(base()..['autoBuyer'] = 'yes'), [
        'autoBuyer must be an object',
      ]);
    });
  });
}
