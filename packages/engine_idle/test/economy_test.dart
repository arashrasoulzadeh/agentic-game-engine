import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

typedef _Game = ({
  World world,
  BigTreasury wallet,
  EntityId cursor,
  EntityId farm,
});

_Game _game({String coins = '1000'}) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerIdleComponents(w);
  final wallet = BigTreasury(amounts: {'coins': n(coins)});
  w.storeOf<BigTreasury>().set(w.spawn(), wallet);

  final cursor = w.spawn();
  w.storeOf<Generator>().set(
    cursor,
    Generator(
      id: 'cursor',
      cost: GeometricCost(base: n('10'), growth: 1.15),
      output: {'coins': n('0.1')},
    ),
  );
  final farm = w.spawn();
  w.storeOf<Generator>().set(
    farm,
    Generator(
      id: 'farm',
      cost: GeometricCost(base: n('100'), growth: 1.2),
      output: {'coins': n('5')},
      maxOwned: 3,
    ),
  );
  return (world: w, wallet: wallet, cursor: cursor, farm: farm);
}

Upgrade _upgrade(
  World w, {
  String target = 'cursor',
  String cost = '50',
  String mult = '2',
  List<String> requires = const [],
}) {
  final e = w.spawn();
  final u = Upgrade(
    id: 'u_$target',
    target: target,
    multiplier: n(mult),
    cost: {'coins': n(cost)},
    requires: requires,
  );
  w.storeOf<Upgrade>().set(e, u);
  return u;
}

void main() {
  group('milestones', () {
    test('reached milestones multiply that generator and stack', () {
      final g = _game();
      final cursor = g.world.storeOf<Generator>().get(g.cursor)!;
      cursor.milestones.addAll([Milestone(10, n('2')), Milestone(20, n('3'))]);
      cursor.owned = 9;
      expect(computeIncome(g.world)['coins']!.approxEquals(n('0.9')), isTrue);
      cursor.owned = 10;
      expect(computeIncome(g.world)['coins']!.approxEquals(n('2')), isTrue);
      cursor.owned = 20;
      expect(computeIncome(g.world)['coins']!.approxEquals(n('12')), isTrue);
    });

    test('survive a JSON round trip', () {
      final g = Generator(
        id: 'x',
        cost: GeometricCost(base: n('1'), growth: 1.1),
        milestones: [Milestone(25, n('2'))],
      );
      final back = Generator.fromJson(g.toJson());
      expect(back.milestones.single.owned, 25);
      expect(back.milestones.single.multiplier, n('2'));
    });
  });

  group('income', () {
    test('owned x output, summed over generators', () {
      final g = _game();
      g.world.storeOf<Generator>().get(g.cursor)!.owned = 10;
      g.world.storeOf<Generator>().get(g.farm)!.owned = 2;
      expect(
        computeIncome(g.world)['coins']!.approxEquals(n('11')),
        isTrue,
        reason: '10*0.1 + 2*5',
      );
    });

    test(
      'purchased upgrades multiply their target (or all); unpurchased ones do not',
      () {
        final g = _game();
        g.world.storeOf<Generator>().get(g.cursor)!.owned = 10;
        g.world.storeOf<Generator>().get(g.farm)!.owned = 1;
        final doubleCursor = _upgrade(g.world);
        _upgrade(g.world, target: 'all', mult: '3').purchased = false;
        expect(
          computeIncome(g.world)['coins']!.approxEquals(n('6')),
          isTrue,
          reason: '1 + 5, nothing bought',
        );

        doubleCursor.purchased = true;
        expect(
          computeIncome(g.world)['coins']!.approxEquals(n('7')),
          isTrue,
          reason: '10*0.1*2 + 5',
        );
      },
    );

    test('game-wide modifiers (prestige, boosts) multiply everything', () {
      final g = _game();
      g.world.storeOf<Generator>().get(g.farm)!.owned = 2;
      final mods = IdleModifiers()
        ..stack.setMultiplier('prestige', n('4'))
        ..stack.setMultiplier('boost', n('2'));
      g.world.storeOf<IdleModifiers>().set(g.world.spawn(), mods);
      expect(
        computeIncome(g.world)['coins']!.approxEquals(n('80')),
        isTrue,
        reason: '2*5*4*2',
      );
      mods.stack.remove('boost');
      expect(computeIncome(g.world)['coins']!.approxEquals(n('40')), isTrue);
    });

    test('with nothing owned there is no income', () {
      expect(computeIncome(_game().world), isEmpty);
    });

    test('synergy upgrades scale with owned count of synergyOf', () {
      final g = _game();
      g.world.storeOf<Generator>().get(g.cursor)!.owned = 10;
      g.world.storeOf<Generator>().get(g.farm)!.owned = 1;
      // farms: 5/s base; +1% per cursor → 5 * (1 + 0.01*10) = 5.5
      final syn = Upgrade(
        id: 'syn',
        target: 'farm',
        bonusPerOwned: n('0.01'),
        synergyOf: 'cursor',
        cost: {'coins': n('1')},
      )..purchased = true;
      g.world.storeOf<Upgrade>().set(g.world.spawn(), syn);
      expect(
        computeIncome(g.world)['coins']!.approxEquals(n('6.5')),
        isTrue,
        reason: '10*0.1 + 5*(1+0.1)',
      );
      final back = Upgrade.fromJson(syn.toJson());
      expect(back.bonusPerOwned, n('0.01'));
      expect(back.synergyOf, 'cursor');
    });
  });

  group('buying generators', () {
    test(
      'buying one spends its price, raises the count and updates the wallet\'s income',
      () {
        final g = _game();
        final r = buyGenerator(g.world, g.wallet, g.cursor);
        expect(r.ok, isTrue);
        expect(r.spent['coins'], n('10'));
        expect(g.world.storeOf<Generator>().get(g.cursor)!.owned, 1);
        expect(g.wallet.of('coins'), n('990'));
        expect(g.wallet.rateOf('coins').approxEquals(n('0.1')), isTrue);
      },
    );

    test('buy ×10 costs the closed-form total and is all or nothing', () {
      final g = _game(coins: '300');
      final curve = GeometricCost(base: n('10'), growth: 1.15);
      final r = buyGenerator(g.world, g.wallet, g.cursor, count: 10);
      expect(r.bought, 10);
      expect(r.spent['coins']!.approxEquals(curve.totalCost(0, 10)), isTrue);

      final poor = _game(coins: '50');
      final fail = buyGenerator(
        poor.world,
        poor.wallet,
        poor.cursor,
        count: 10,
      );
      expect(fail.ok, isFalse);
      expect(fail.failure, BuyFailure.unaffordable);
      expect(poor.wallet.of('coins'), n('50'), reason: 'nothing taken');
      expect(poor.world.storeOf<Generator>().get(poor.cursor)!.owned, 0);
    });

    test('max buys as many as the budget affords, exactly', () {
      final g = _game(coins: '1000');
      final curve = GeometricCost(base: n('10'), growth: 1.15);
      final r = buyGenerator(g.world, g.wallet, g.cursor, count: null);
      expect(r.bought, curve.maxAffordable(0, n('1000')));
      expect(r.bought, greaterThan(10));
      expect(g.wallet.of('coins') >= BigNumber.zero, isTrue);
      expect(curve.totalCost(r.bought + 1 - 1, 1) > BigNumber.zero, isTrue);
    });

    test('the ownership cap limits the purchase', () {
      final g = _game(coins: '1e9');
      expect(
        buyGenerator(g.world, g.wallet, g.farm, count: 10).bought,
        3,
        reason: 'maxOwned 3',
      );
      final again = buyGenerator(g.world, g.wallet, g.farm);
      expect(again.failure, BuyFailure.maxOwned);
      expect(
        buyGenerator(g.world, g.wallet, g.farm, count: null).failure,
        BuyFailure.maxOwned,
      );
    });

    test(
      'a generator needing a technology is locked until the team has it',
      () {
        final g = _game();
        final locked = g.world.spawn();
        g.world.storeOf<Generator>().set(
          locked,
          Generator(
            id: 'lab',
            cost: GeometricCost(base: n('1'), growth: 1.1),
            output: {'coins': n('9')},
            requires: ['science'],
          ),
        );
        expect(
          buyGenerator(g.world, g.wallet, locked).failure,
          BuyFailure.locked,
        );
        grantTech(g.world, 'player', 'science');
        expect(buyGenerator(g.world, g.wallet, locked).ok, isTrue);
      },
    );

    test('a missing entity is a no-op', () {
      final g = _game();
      expect(buyGenerator(g.world, g.wallet, 9999).failure, BuyFailure.nothing);
    });
  });

  group('buying upgrades', () {
    test(
      'an upgrade is bought once, spends its cost, and multiplies the target from then on',
      () {
        final g = _game(coins: '200');
        buyGenerator(g.world, g.wallet, g.cursor, count: 10);
        final before = g.wallet.rateOf('coins');
        final e = g.world.spawn();
        g.world.storeOf<Upgrade>().set(
          e,
          Upgrade(
            id: 'x2',
            target: 'cursor',
            multiplier: n('2'),
            cost: {'coins': n('50')},
          ),
        );
        final money = g.wallet.of('coins');
        final r = buyUpgrade(g.world, g.wallet, e);
        expect(r.ok, isTrue);
        expect(g.wallet.of('coins'), money - n('50'));
        expect(g.wallet.rateOf('coins').approxEquals(before * n('2')), isTrue);
        expect(
          buyUpgrade(g.world, g.wallet, e).failure,
          BuyFailure.alreadyBought,
        );
      },
    );

    test('too poor, or locked, buys nothing', () {
      final g = _game(coins: '5');
      final e = g.world.spawn();
      g.world.storeOf<Upgrade>().set(
        e,
        Upgrade(id: 'x', multiplier: n('2'), cost: {'coins': n('50')}),
      );
      expect(buyUpgrade(g.world, g.wallet, e).failure, BuyFailure.unaffordable);
      expect(g.world.storeOf<Upgrade>().get(e)!.purchased, isFalse);

      final locked = g.world.spawn();
      g.world.storeOf<Upgrade>().set(
        locked,
        Upgrade(id: 'y', multiplier: n('2'), requires: ['magic']),
      );
      expect(buyUpgrade(g.world, g.wallet, locked).failure, BuyFailure.locked);
    });
  });

  group('running live', () {
    test('IdleSystem accrues the wallet at the computed rate', () {
      final g = _game(coins: '100');
      buyGenerator(g.world, g.wallet, g.farm); // 5 coins/s
      g.world.addSystem(IdleSystem());
      final before = g.wallet.of('coins');
      for (var i = 0; i < 10; i++) {
        g.world.step(1);
      }
      expect((g.wallet.of('coins') - before).approxEquals(n('50')), isTrue);
    });

    test('live play and offline catch-up agree', () {
      final live = _game(coins: '10000');
      buyGenerator(live.world, live.wallet, live.farm, count: 3);
      live.world.addSystem(IdleSystem());
      for (var i = 0; i < 3600; i++) {
        live.world.step(1);
      }

      final offline = _game(coins: '10000');
      buyGenerator(offline.world, offline.wallet, offline.farm, count: 3);
      final t0 = DateTime.utc(2026);
      OfflineProgress.catchUp(
        offline.wallet,
        lastActiveAt: t0,
        now: t0.add(const Duration(hours: 1)),
      );

      expect(
        live.wallet
            .of('coins')
            .approxEquals(offline.wallet.of('coins'), relative: 1e-9),
        isTrue,
      );
    });
  });
}
