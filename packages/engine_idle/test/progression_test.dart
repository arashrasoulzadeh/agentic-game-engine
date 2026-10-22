import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

class _Game {
  _Game({String coins = '0'}) {
    registerCoreComponents(world);
    registerIdleComponents(world);
    wallet = BigTreasury(amounts: {'coins': n(coins)});
    world.storeOf<BigTreasury>().set(world.spawn(), wallet);
    world.storeOf<IdleStats>().set(world.spawn(), stats);
    world.storeOf<IdleModifiers>().set(world.spawn(), mods);
    cursor = world.spawn();
    world.storeOf<Generator>().set(
      cursor,
      Generator(
        id: 'cursor',
        cost: GeometricCost(base: n('10'), growth: 1.15),
        output: {'coins': n('1')},
      ),
    );
  }

  final world = World(width: 10, height: 10);
  late BigTreasury wallet;
  final stats = IdleStats();
  final mods = IdleModifiers();
  late EntityId cursor;

  PrestigeRule addRule({
    bool keepUpgrades = false,
    List<String> keepGenerators = const [],
    Map<String, BigNumber>? start,
  }) {
    final rule = PrestigeRule(
      currency: 'gems',
      basedOn: 'coins',
      divisor: n('1e6'),
      exponent: 0.5,
      bonusPerUnit: 0.1,
      startingAmounts: start ?? {'coins': n('10')},
      keepUpgrades: keepUpgrades,
      keepGenerators: keepGenerators,
    );
    world.storeOf<PrestigeRule>().set(world.spawn(), rule);
    return rule;
  }
}

void main() {
  group('game events and achievements', () {
    test(
      'recordIdleEvent counts and unlocks event: achievements, surviving a save',
      () {
        final g = _Game();
        g.world.storeOf<Achievement>().set(
          g.world.spawn(),
          Achievement(id: 'slayer', stat: 'event:dragon', atLeast: n('3')),
        );
        expect(recordIdleEvent(g.world, g.wallet, 'dragon', 2), isEmpty);
        expect(recordIdleEvent(g.world, g.wallet, 'dragon'), ['slayer']);
        expect(g.stats.eventCounts['dragon'], 3);
        final back = IdleStats.fromJson(g.stats.toJson());
        expect(back.eventCounts['dragon'], 3);
      },
    );

    test(
      'an unknown event name is zero, and a non-positive count is ignored',
      () {
        final g = _Game();
        expect(achievementValue(g.world, 'event:nothing'), BigNumber.zero);
        expect(recordIdleEvent(g.world, g.wallet, 'x', 0), isEmpty);
        expect(g.stats.eventCounts, isEmpty);
      },
    );
  });

  group('stats', () {
    test(
      'IdleSystem records earnings into the run and lifetime totals, and play time',
      () {
        final g = _Game();
        g.wallet.incomePerSecond['coins'] = n('5');
        g.world.addSystem(IdleSystem());
        for (var i = 0; i < 10; i++) {
          g.world.step(1);
        }
        expect(g.stats.runEarned['coins']!.approxEquals(n('50')), isTrue);
        expect(g.stats.lifetimeEarned['coins']!.approxEquals(n('50')), isTrue);
        expect(g.stats.secondsPlayed, closeTo(10, 1e-9));
      },
    );

    test('credit adds an offline summary to the totals', () {
      final g = _Game();
      g.wallet.incomePerSecond['coins'] = n('2');
      final t0 = DateTime.utc(2026);
      final summary = OfflineProgress.catchUp(
        g.wallet,
        lastActiveAt: t0,
        now: t0.add(const Duration(hours: 1)),
      );
      g.stats.credit(summary.gained);
      expect(g.stats.lifetimeEarned['coins']!.approxEquals(n('7200')), isTrue);
      expect(g.stats.secondsPlayed, 0, reason: 'offline time is not play time');
    });

    test('stats survive JSON', () {
      final s = IdleStats(
        runEarned: {'coins': n('1e30')},
        lifetimeEarned: {'coins': n('9e40')},
        prestigeCount: 3,
        taps: 12,
        secondsPlayed: 99.5,
      );
      final back = IdleStats.fromJson(
        jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>,
      );
      expect(back.lifetimeEarned['coins'], n('9e40'));
      expect(
        (back.prestigeCount, back.taps, back.secondsPlayed),
        (3, 12, 99.5),
      );
    });
  });

  group('prestige', () {
    test(
      'the gain is floor((earned / divisor) ^ exponent), zero below one unit',
      () {
        final rule = PrestigeRule(
          currency: 'gems',
          basedOn: 'coins',
          divisor: n('1e6'),
        );
        expect(rule.gainFor(n('0')), BigNumber.zero);
        expect(rule.gainFor(n('999999')), BigNumber.zero);
        expect(rule.gainFor(n('1e6')), n('1'));
        expect(rule.gainFor(n('4e6')), n('2'));
        expect(rule.gainFor(n('1e12')), n('1000'));
        expect(
          rule.gainFor(n('9.9e11')),
          n('994'),
          reason: 'floor(sqrt(990000))',
        );
      },
    );

    test('prestiging resets the run, banks the currency and boosts income', () {
      final g = _Game(coins: '5e7');
      g.addRule();
      g.stats.credit({'coins': n('4e12')});
      buyGenerator(g.world, g.wallet, g.cursor, count: 5);
      final upgrade = g.world.spawn();
      g.world.storeOf<Upgrade>().set(
        upgrade,
        Upgrade(id: 'x2', multiplier: n('2'), purchased: true),
      );

      expect(prestigeGainNow(g.world), n('2000'), reason: 'sqrt(4e12 / 1e6)');
      final gain = performPrestige(g.world, g.wallet);

      expect(gain, n('2000'));
      expect(g.wallet.of('gems'), n('2000'));
      expect(
        g.wallet.of('coins'),
        n('10'),
        reason: 'back to the starting amount',
      );
      expect(g.world.storeOf<Generator>().get(g.cursor)!.owned, 0);
      expect(g.world.storeOf<Upgrade>().get(upgrade)!.purchased, isFalse);
      expect(g.stats.runEarned, isEmpty);
      expect(
        g.stats.lifetimeEarned['coins'],
        n('4e12'),
        reason: 'lifetime is kept',
      );
      expect(g.stats.prestigeCount, 1);
      expect(
        g.mods.stack.totalMultiplier.approxEquals(n('201')),
        isTrue,
        reason: '1 + 0.1 * 2000',
      );

      buyGenerator(g.world, g.wallet, g.cursor);
      expect(
        g.wallet.rateOf('coins').approxEquals(n('201')),
        isTrue,
        reason: '1 cursor x 201 prestige bonus',
      );
    });

    test(
      'the permanent currency survives repeated prestiges and accumulates',
      () {
        final g = _Game();
        g.addRule();
        g.stats.credit({'coins': n('1e6')});
        performPrestige(g.world, g.wallet);
        g.stats.credit({'coins': n('4e6')});
        performPrestige(g.world, g.wallet);
        expect(g.wallet.of('gems'), n('3'), reason: '1 + 2');
        expect(g.stats.prestigeCount, 2);
        expect(g.mods.stack.totalMultiplier.approxEquals(n('1.3')), isTrue);
      },
    );

    test('too early to prestige: nothing changes', () {
      final g = _Game(coins: '500');
      g.addRule();
      g.stats.credit({'coins': n('999')});
      expect(performPrestige(g.world, g.wallet), isNull);
      expect(g.wallet.of('coins'), n('500'));
      expect(g.stats.prestigeCount, 0);
    });

    test('keepUpgrades keeps purchased upgrades', () {
      final g = _Game();
      g.addRule(keepUpgrades: true);
      g.stats.credit({'coins': n('1e6')});
      final e = g.world.spawn();
      g.world.storeOf<Upgrade>().set(
        e,
        Upgrade(id: 'u', multiplier: n('2'), purchased: true),
      );
      performPrestige(g.world, g.wallet);
      expect(g.world.storeOf<Upgrade>().get(e)!.purchased, isTrue);
    });

    test('keepGenerators keeps only the named generators', () {
      final g = _Game();
      g.addRule(keepGenerators: ['cursor']);
      g.stats.credit({'coins': n('1e6')});
      final other = g.world.spawn();
      g.world.storeOf<Generator>().set(
        other,
        Generator(
          id: 'farm',
          owned: 4,
          cost: GeometricCost(base: n('10'), growth: 1.1),
        ),
      );
      final cursor = g.world.storeOf<Generator>().get(g.cursor)!;
      cursor.owned = 7;
      performPrestige(g.world, g.wallet);
      expect(cursor.owned, 7);
      expect(g.world.storeOf<Generator>().get(other)!.owned, 0);
    });

    test('without a rule or stats it does nothing', () {
      final w = World(width: 10, height: 10);
      registerCoreComponents(w);
      registerIdleComponents(w);
      expect(performPrestige(w, BigTreasury()), isNull);
      expect(prestigeGainNow(w), BigNumber.zero);
    });

    test('the rule survives JSON', () {
      final rule = _Game().addRule(keepUpgrades: true);
      final back = PrestigeRule.fromJson(
        jsonDecode(jsonEncode(rule.toJson())) as Map<String, dynamic>,
      );
      expect(
        (back.currency, back.exponent, back.keepUpgrades),
        ('gems', 0.5, true),
      );
      expect(back.divisor, n('1e6'));
      expect(back.startingAmounts['coins'], n('10'));
    });
  });

  group('achievements', () {
    Achievement add(
      _Game g,
      String id,
      String stat,
      String atLeast, {
      String reward = '1',
    }) {
      final a = Achievement(
        id: id,
        stat: stat,
        atLeast: n(atLeast),
        reward: n(reward),
      );
      g.world.storeOf<Achievement>().set(g.world.spawn(), a);
      return a;
    }

    test('unlocks when the stat reaches the goal, once, and announces it', () {
      final g = _Game(coins: '1e6');
      final a = add(g, 'rich', 'lifetime:coins', '1000');
      final heard = <String>[];
      g.world.events.on<AchievementUnlockedEvent>((e) => heard.add(e.id));

      expect(checkAchievements(g.world, g.wallet), isEmpty);
      g.stats.credit({'coins': n('1500')});
      expect(checkAchievements(g.world, g.wallet), ['rich']);
      g.world.events.flush();
      expect(heard, ['rich']);
      expect(a.unlocked, isTrue);
      expect(
        checkAchievements(g.world, g.wallet),
        isEmpty,
        reason: 'only once',
      );
    });

    test('every kind of stat can be measured', () {
      final g = _Game(coins: '1e9');
      buyGenerator(g.world, g.wallet, g.cursor, count: 4);
      g.stats
        ..credit({'coins': n('50')})
        ..prestigeCount = 2
        ..taps = 7
        ..secondsPlayed = 33;
      expect(achievementValue(g.world, 'owned:cursor'), n('4'));
      expect(achievementValue(g.world, 'owned:nothing'), BigNumber.zero);
      expect(achievementValue(g.world, 'lifetime:coins'), n('50'));
      expect(achievementValue(g.world, 'run:coins'), n('50'));
      expect(achievementValue(g.world, 'prestiges'), n('2'));
      expect(achievementValue(g.world, 'taps'), n('7'));
      expect(achievementValue(g.world, 'seconds'), n('33'));
      expect(achievementValue(g.world, 'bogus'), BigNumber.zero);
    });

    test('a reward becomes a permanent multiplier and raises income', () {
      final g = _Game(coins: '1e6');
      buyGenerator(g.world, g.wallet, g.cursor, count: 10);
      add(g, 'ten', 'owned:cursor', '10', reward: '2');
      final before = g.wallet.rateOf('coins');
      checkAchievements(g.world, g.wallet);
      expect(g.mods.stack.sources, contains('achievement:ten'));
      expect(g.wallet.rateOf('coins').approxEquals(before * n('2')), isTrue);
    });

    test('achievements and their unlocked state survive JSON', () {
      final a = Achievement(
        id: 'x',
        stat: 'taps',
        atLeast: n('100'),
        reward: n('1.5'),
        unlocked: true,
        name: 'Clicker',
      );
      final back = Achievement.fromJson(
        jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>,
      );
      expect((back.id, back.unlocked, back.name), ('x', true, 'Clicker'));
      expect(back.reward, n('1.5'));
    });
  });
}
