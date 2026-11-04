import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zarvan_idle/zarvan_idle.dart';

const _strength = HeroUpgrade(
  id: 's',
  label: 'S',
  stat: 'attack',
  perLevel: 0.5,
  baseCost: 10,
);

void main() {
  group('HeroProgress persistence', () {
    test('round-trips everything through JSON', () {
      final p = HeroProgress(
        coins: 55,
        stars: 2,
        bestWave: 7,
        kills: 31,
        runs: 4,
      )..buy(_strength);
      p.equipIfBetter(
        const Gear(
          slot: 'weapon',
          name: 'Sword',
          stat: 'attack',
          bonus: 0.2,
          rarity: GearRarity.rare,
        ),
      );
      p.markHintSeen('upgrade');
      p.lastActiveMs = 1234;
      final back = HeroProgress.fromJson(p.toJson());
      expect(back.coins, 45);
      expect(back.levelOf(_strength), 1);
      expect((back.stars, back.bestWave, back.kills, back.runs), (2, 7, 31, 4));
      expect(back.gear['weapon']!.name, 'Sword');
      expect(back.gear['weapon']!.rarity, GearRarity.rare);
      expect(back.hintsSeen, {'upgrade'});
      expect(back.lastActiveMs, 1234);
    });

    test('fromJson tolerates an empty or older save', () {
      final p = HeroProgress.fromJson({});
      expect((p.coins, p.stars, p.bestWave), (0, 0, 0));
    });

    test('onChanged fires for every kind of change worth saving', () {
      var n = 0;
      final p = HeroProgress(coins: 100, onChanged: () => n++);
      p.buy(_strength);
      p.addCoins(5);
      p.recordKill();
      p.startRun();
      p.reachWave(3);
      p.equipIfBetter(const Gear(slot: 'a', name: 'n', stat: 'hp', bonus: 1));
      p.markHintSeen('x');
      p.ascend();
      expect(n, 8);
      p.reachWave(0); // not higher: no change
      p.markHintSeen('x'); // already seen
      expect(n, 8);
    });
  });

  group('checkpoints, prestige and gear', () {
    test('a checkpoint is the best wave rounded down to a multiple', () {
      final p = HeroProgress()..bestWave = 12;
      expect(p.checkpoint(5), 10);
      expect(p.checkpoint(0), 0);
      expect(p.checkpoint(20), 0);
    });

    test('ascend gives a star and resets coins, levels and best wave only', () {
      final p = HeroProgress(coins: 100, kills: 9)..buy(_strength);
      p.bestWave = 8;
      p.equipIfBetter(
        const Gear(slot: 'w', name: 'n', stat: 'attack', bonus: 0.1),
      );
      p.ascend();
      expect(
        (p.stars, p.coins, p.bestWave, p.levelOf(_strength)),
        (1, 0, 0, 0),
      );
      expect((p.kills, p.gear.length), (9, 1));
    });

    test(
      'gear only replaces a worse item in its slot and adds up per stat',
      () {
        final p = HeroProgress();
        const small = Gear(
          slot: 'weapon',
          name: 'a',
          stat: 'attack',
          bonus: 0.1,
        );
        const big = Gear(slot: 'weapon', name: 'b', stat: 'attack', bonus: 0.3);
        const charm = Gear(
          slot: 'charm',
          name: 'c',
          stat: 'attack',
          bonus: 0.05,
        );
        expect(p.equipIfBetter(small), isTrue);
        expect(p.equipIfBetter(small), isFalse);
        expect(p.equipIfBetter(big), isTrue);
        expect(p.equipIfBetter(small), isFalse);
        p.equipIfBetter(charm);
        expect(p.gearBonus('attack'), closeTo(0.35, 1e-9));
        expect(p.gearBonus('hp'), 0);
      },
    );
  });

  group('OfflineRule', () {
    const rule = OfflineRule(
      coinsPerMinute: 10,
      perWaveGrowth: 0.5,
      efficiency: 0.5,
      capHours: 2,
    );

    test('earns coins per minute away, discounted and grown by best wave', () {
      final p = HeroProgress()..bestWave = 2; // rate 10 * (1 + 1) = 20/min
      expect(rule.coins(p, const Duration(minutes: 10)), 100); // 20*10*0.5
    });

    test('is capped, and earns nothing for a short absence', () {
      final p = HeroProgress();
      expect(
        rule.coins(p, const Duration(hours: 50)),
        rule.coins(p, const Duration(hours: 2)),
      );
      expect(rule.coins(p, const Duration(seconds: 30)), 0);
    });

    test('stars raise the rate', () {
      final plain = HeroProgress();
      final starred = HeroProgress(stars: 5);
      expect(
        rule.coins(starred, const Duration(hours: 1)),
        greaterThan(rule.coins(plain, const Duration(hours: 1))),
      );
    });
  });

  group('HeroProgressStore', () {
    test('saves on every change and loads it back', () {
      final mem = MemorySaveStore();
      final a = HeroProgressStore(mem).load();
      a.addCoins(42);
      final b = HeroProgressStore(mem).load();
      expect(b.coins, 42);
    });

    test('credits offline earnings once, from the time of the last save', () {
      final mem = MemorySaveStore();
      var now = DateTime(2026, 1, 1, 12);
      final first = HeroProgressStore(mem, clock: () => now).load();
      first.addCoins(10);
      now = now.add(const Duration(hours: 1));
      const rule = OfflineRule(
        coinsPerMinute: 10,
        efficiency: 1,
        perWaveGrowth: 0,
      );
      final again = HeroProgressStore(mem, clock: () => now).load(rule: rule);
      expect(again.pendingOfflineCoins, 600);
      expect(again.coins, 610);
      expect(again.pendingOfflineAway, const Duration(hours: 1));
      // loading again straight away: the save was re-stamped, nothing is owed
      final third = HeroProgressStore(mem, clock: () => now).load(rule: rule);
      expect(third.pendingOfflineCoins, 0);
    });

    test('shares a save map with other keys without clobbering them', () {
      final mem = MemorySaveStore()..value = {'other': 1};
      HeroProgressStore(mem).load().addCoins(1);
      expect(mem.value!['other'], 1);
      expect(mem.value!['waveCombat'], isA<Map>());
    });
  });

  group('PrefsSaveStore', () {
    test('keeps a save across opens and ignores corrupt data', () async {
      SharedPreferences.setMockInitialValues({});
      final a = await PrefsSaveStore.open('k');
      expect(a.read(), isNull);
      a.write({'x': 1});
      final b = await PrefsSaveStore.open('k');
      expect(b.read(), {'x': 1});
      SharedPreferences.setMockInitialValues({'k': '{not json'});
      expect((await PrefsSaveStore.open('k')).read(), isNull);
    });
  });
}
