import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart' hide StatusEffect, StatusEffects;
import 'package:zarvan_flutter/zarvan_flutter.dart' as eng;
import 'package:zarvan_idle/zarvan_idle.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart';

World _world() {
  final world = World(width: 180, height: 320);
  registerCoreComponents(world);
  eng.registerFlutterComponents(world);
  registerWaveCombatComponents(world);
  return world;
}

EntityId _fighter(
  World world,
  String side, {
  double hp = 100,
  double attack = 10,
  double speed = 1,
  EnemyPowers? powers,
}) => spawnFighter(
  world,
  side: side,
  x: side == 'hero' ? 40 : 120,
  y: 200,
  hp: hp,
  attack: attack,
  attackSpeed: speed,
  armor: 0,
  atlasId: 'a',
  frameCount: 1,
  powers: powers,
);

void main() {
  group('power text parsing for conditions', () {
    test('bleed, poison, stun and volley are read from sidecar text', () {
      final p = EnemyPowers.parse([
        'hits apply bleed: 2% hero max hp/s for 3s',
        'hits poison: 2.5% hero max hp/s for 4s, stacks x3',
        '15% chance per hit to stun the hero 0.5s',
        'every 4th attack fires 3 arrows, each 60% damage',
      ])!;
      expect((p.bleedFraction, p.bleedSeconds), (0.02, 3));
      expect(
        (p.poisonFraction, p.poisonSeconds, p.poisonMaxStacks),
        (0.025, 4, 3),
      );
      expect((p.stunChance, p.stunSeconds), (0.15, 0.5));
      expect((p.volleyEvery, p.volleyArrows, p.volleyDamage), (4, 3, 0.6));
      final back = EnemyPowers.fromJson(p.toJson());
      expect(
        (back.bleedFraction, back.volleyEvery, back.stunChance),
        (0.02, 4, 0.15),
      );
    });

    test('immune-to-stun style text alone stays unrecognised', () {
      expect(EnemyPowers.parse(['immune to stun']), isNull);
    });
  });

  group('Conditions', () {
    test('a repeat refreshes; stackable kinds add a stack up to the cap', () {
      final c = Conditions();
      c.apply(
        ConditionKind.poison,
        seconds: 4,
        dpsFraction: 0.02,
        maxStacks: 2,
      );
      c.apply(
        ConditionKind.poison,
        seconds: 4,
        dpsFraction: 0.02,
        maxStacks: 2,
      );
      c.apply(
        ConditionKind.poison,
        seconds: 4,
        dpsFraction: 0.02,
        maxStacks: 2,
      );
      expect(c.active.single.stacks, 2);
      c.apply(ConditionKind.bleed, seconds: 3, dpsFraction: 0.01);
      expect(c.active.length, 2);
      expect(c.stunned, isFalse);
      c.apply(ConditionKind.stun, seconds: 1);
      expect(c.stunned, isTrue);
      expect(c.describe(), contains('Poison x2'));
    });

    test('JSON round-trips', () {
      final c = Conditions()
        ..apply(ConditionKind.bleed, seconds: 3, dpsFraction: 0.02);
      final back = Conditions.fromJson(c.toJson());
      expect(
        (back.active.single.kind, back.active.single.dpsFraction),
        (ConditionKind.bleed, 0.02),
      );
    });

    test('bleed drains max-health fractions over time, then expires', () {
      final world = _world()..addSystem(ConditionSystem());
      final hero = _fighter(world, 'hero', hp: 100);
      world.componentsOf<Conditions>().set(
        hero,
        Conditions()..apply(ConditionKind.bleed, seconds: 2, dpsFraction: 0.1),
      );
      final ticks = <ConditionTick>[];
      world.events.on<ConditionTick>(ticks.add);
      for (var i = 0; i < 25; i++) {
        world.step(0.1);
      }
      // 10% of 100 per second for 2 seconds.
      expect(world.componentsOf<Health>().get(hero)!.current, closeTo(80, 0.5));
      expect(world.componentsOf<Conditions>().get(hero)!.active, isEmpty);
      expect(ticks, isNotEmpty);
      expect(ticks.fold<double>(0, (s, t) => s + t.damage), closeTo(20, 1));
    });
  });

  group('conditions in combat', () {
    test('an enemy with bleed puts it on the hero when it hits', () {
      final world = _world()..addSystem(AutoCombatSystem());
      final hero = _fighter(world, 'hero', hp: 1000, attack: 0.1, speed: 0.01);
      _fighter(
        world,
        'enemy',
        attack: 1,
        powers: EnemyPowers(bleedFraction: 0.02, bleedSeconds: 3),
      );
      world.step(0.01);
      final c = world.componentsOf<Conditions>().get(hero)!;
      expect(c.active.single.kind, ConditionKind.bleed);
    });

    test('a stunned fighter does not attack until it wears off', () {
      final world = _world()
        ..addSystem(AutoCombatSystem())
        ..addSystem(ConditionSystem());
      final hits = <FighterHit>[];
      world.events.on<FighterHit>(hits.add);
      final hero = _fighter(world, 'hero', hp: 1000, attack: 5, speed: 10);
      _fighter(world, 'enemy', hp: 1000, attack: 1, speed: 0.01);
      world.componentsOf<Conditions>().set(
        hero,
        Conditions()..apply(ConditionKind.stun, seconds: 0.5),
      );
      for (var i = 0; i < 4; i++) {
        world.step(0.1);
      }
      expect(hits.where((h) => h.attackerSide == 'hero'), isEmpty);
      for (var i = 0; i < 4; i++) {
        world.step(0.1);
      }
      expect(hits.where((h) => h.attackerSide == 'hero'), isNotEmpty);
    });

    test('every Nth attack is a volley of lighter arrows', () {
      final world = _world()..addSystem(AutoCombatSystem());
      final hits = <FighterHit>[];
      world.events.on<FighterHit>(hits.add);
      _fighter(world, 'hero', hp: 1e6, attack: 0.01, speed: 0.01);
      _fighter(
        world,
        'enemy',
        attack: 10,
        speed: 100,
        powers: EnemyPowers(volleyEvery: 3, volleyArrows: 3, volleyDamage: 0.5),
      );
      for (var i = 0; i < 4; i++) {
        world.step(0.12); // speed is clamped to 10/s: one attack per 0.1 s
      }
      final enemy = hits.where((h) => h.attackerSide == 'enemy').toList();
      // attacks 1 and 2 are single 10s; attack 3 is three 5s; attack 4 a 10.
      expect(enemy.map((h) => h.damage).toList(), [10, 10, 5, 5, 5, 10]);
    });

    test('damage modifiers multiply together per side', () {
      final system = AutoCombatSystem()
        ..damageModifiers.add((s) => s == 'hero' ? 2 : 1)
        ..damageModifiers.add((s) => s == 'hero' ? 1.5 : 0.5);
      expect(system.damageFactor('hero'), 3);
      expect(system.damageFactor('enemy'), 0.5);
      expect(AutoCombatSystem().damageFactor('hero'), 1);
    });
  });

  group('LootTable', () {
    const table = LootTable(
      normalChance: 1,
      eliteChance: 1,
      treasureChance: 1,
      waveGrowth: 0.1,
    );

    test('rolls gear of a slot with the right stat, growing with the wave', () {
      final low = table.roll(math.Random(1), WaveKind.normal, 0)!;
      final high = table.roll(math.Random(1), WaveKind.normal, 10)!;
      final slot = table.slots.firstWhere((s) => s.slot == low.slot);
      expect(low.stat, slot.stat);
      expect(slot.names, contains(low.name));
      expect(high.bonus, closeTo(low.bonus * 2, 1e-9)); // 1 + 0.1 * 10
    });

    test('chance 0 drops nothing; treasure always drops rare or better', () {
      const none = LootTable(normalChance: 0);
      expect(none.roll(math.Random(1), WaveKind.normal, 3), isNull);
      for (var s = 0; s < 30; s++) {
        final g = table.roll(math.Random(s), WaveKind.treasure, 0)!;
        expect(g.rarity, isNot(GearRarity.common));
      }
    });

    test('elites drop better gear on average than normal enemies', () {
      double avg(WaveKind k) {
        var total = 0.0;
        for (var s = 0; s < 400; s++) {
          total += table.roll(math.Random(s), k, 0)!.bonus;
        }
        return total / 400;
      }

      expect(avg(WaveKind.elite), greaterThan(avg(WaveKind.normal)));
    });
  });

  group('skills', () {
    const strike = HeroSkill(
      id: 'strike',
      label: 'Strike',
      kind: SkillKind.strike,
      cooldown: 10,
    );

    test('a used skill is on cooldown until it ticks down', () {
      final cd = SkillCooldowns(const [strike]);
      expect(cd.ready(strike), isTrue);
      expect(cd.use(strike), isTrue);
      expect(cd.use(strike), isFalse);
      cd.tick(4);
      expect(cd.remaining(strike), closeTo(6, 1e-9));
      cd.tick(7);
      expect(cd.ready(strike), isTrue);
    });
  });

  group('WaveStrings', () {
    test('defaults read naturally and can be replaced', () {
      const s = WaveStrings();
      expect(s.coinsLabel(5), 'Coins 5');
      expect(s.comboLabel(3), 'Combo x3');
      expect(s.retryLabel(1), 'Retry');
      expect(s.retryLabel(6), 'Retry (Wave 6)');
      expect(
        s.summary(wave: 4, killCount: 9, bestWave: 6),
        'Wave 4 · Kills 9 · Best 7',
      );
      expect(s.awayMessage(120), '+120 coins earned while away');
      const fa = WaveStrings(coins: 'سکه', retry: 'دوباره');
      expect(fa.coinsLabel(5), 'سکه 5');
      expect(fa.retryLabel(1), 'دوباره');
    });

    test('gear lines show names and percentages', () {
      const g = Gear(slot: 'w', name: 'Sword', stat: 'attack', bonus: 0.124);
      expect(const WaveStrings().lootLabel(g), 'Loot: Sword +12%');
      expect(
        const WaveStrings().gearSummary([g, g]),
        'Sword +12% · Sword +12%',
      );
    });
  });
}
