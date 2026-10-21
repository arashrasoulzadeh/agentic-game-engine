import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

({World world, BigTreasury wallet, IdleModifiers mods, IdleStats stats})
game() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerIdleComponents(w);
  final wallet = BigTreasury();
  final mods = IdleModifiers();
  final stats = IdleStats();
  w.storeOf<BigTreasury>().set(w.spawn(), wallet);
  w.storeOf<IdleModifiers>().set(w.spawn(), mods);
  w.storeOf<IdleStats>().set(w.spawn(), stats);
  final g = w.spawn();
  w.storeOf<Generator>().set(
    g,
    Generator(
      id: 'g',
      cost: GeometricCost(base: n('1'), growth: 1.1),
      output: {'coins': n('10')},
      owned: 1,
    ),
  );
  recomputeIncome(w, wallet);
  return (world: w, wallet: wallet, mods: mods, stats: stats);
}

void main() {
  group('taps', () {
    test(
      'a tap earns the base amount times the game-wide multiplier and is counted',
      () {
        final g = game();
        g.mods.stack.setMultiplier('prestige', n('3'));
        expect(tapEarn(g.world, g.wallet), n('3'));
        expect(tapEarn(g.world, g.wallet, amount: n('10')), n('30'));
        expect(g.wallet.of('coins'), n('33'));
        expect(g.stats.taps, 2);
        expect(g.stats.lifetimeEarned['coins'], n('33'));
      },
    );

    test('taps work without stats or modifiers in the world', () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      registerIdleComponents(w);
      final wallet = BigTreasury();
      expect(tapEarn(w, wallet, resource: 'gems'), n('1'));
      expect(wallet.of('gems'), n('1'));
    });
  });

  group('boosts', () {
    test('a boost multiplies income while it runs and stops when it ends', () {
      final g = game();
      expect(g.wallet.rateOf('coins').approxEquals(n('10')), isTrue);
      activateBoost(
        g.world,
        g.wallet,
        id: 'x2',
        multiplier: n('2'),
        seconds: 30,
      );
      expect(g.wallet.rateOf('coins').approxEquals(n('20')), isTrue);
      expect(g.mods.stack.sources, contains('boost:x2'));

      g.world.addSystem(BoostSystem());
      for (var i = 0; i < 29; i++) {
        g.world.step(1);
      }
      expect(
        g.wallet.rateOf('coins').approxEquals(n('20')),
        isTrue,
        reason: 'still running at 29 s',
      );
      g.world.step(1.5);
      expect(
        g.wallet.rateOf('coins').approxEquals(n('10')),
        isTrue,
        reason: 'ended',
      );
      expect(g.mods.stack.sources, isNot(contains('boost:x2')));
      expect(g.world.storeOf<Boost>().length, 0);
    });

    test(
      'restarting the same boost refreshes its time instead of stacking',
      () {
        final g = game();
        activateBoost(
          g.world,
          g.wallet,
          id: 'x2',
          multiplier: n('2'),
          seconds: 10,
        );
        g.world.addSystem(BoostSystem());
        g.world.step(8);
        activateBoost(
          g.world,
          g.wallet,
          id: 'x2',
          multiplier: n('2'),
          seconds: 10,
        );
        expect(g.world.storeOf<Boost>().length, 1);
        g.world.step(8);
        expect(
          g.wallet.rateOf('coins').approxEquals(n('20')),
          isTrue,
          reason: 'refreshed to 10 s, 2 s left',
        );
      },
    );

    test('different boosts multiply together', () {
      final g = game();
      activateBoost(
        g.world,
        g.wallet,
        id: 'a',
        multiplier: n('2'),
        seconds: 60,
      );
      activateBoost(
        g.world,
        g.wallet,
        id: 'b',
        multiplier: n('5'),
        seconds: 60,
      );
      expect(g.wallet.rateOf('coins').approxEquals(n('100')), isTrue);
    });

    test('a boost survives a save', () {
      final b = Boost(id: 'x', multiplier: n('2'), remaining: 12.5);
      final back = Boost.fromJson(b.toJson());
      expect((back.id, back.remaining), ('x', 12.5));
      expect(back.multiplier, n('2'));
    });
  });
}
