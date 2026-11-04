import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_idle/zarvan_idle.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart';

class _Fight {
  _Fight(this.world, this.combat, this.hero, this.enemies);
  final World world;
  final AutoCombatSystem combat;
  final EntityId hero;
  final List<EntityId> enemies;

  EntityId get enemy => enemies.first;
  double hp(EntityId e) => world.componentsOf<Health>().get(e)!.current;
  CombatStats stats(EntityId e) => world.componentsOf<CombatStats>().get(e)!;
}

/// A hero (attack 20) against [count] enemies (attack 10). Cooldowns are set by
/// the tests so every swing lands exactly when they say.
_Fight _fight({
  int count = 1,
  double heroCooldown = 100,
  double enemyCooldown = 100,
  bool timing = true,
}) {
  final world = World(width: 180, height: 320);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  registerCombatComponents(world);
  final combat = AutoCombatSystem()
    ..windupSeconds = 0.5
    ..playerTiming = timing;
  world.addSystem(combat);
  final hero = spawnFighter(
    world,
    side: 'hero',
    x: 40,
    y: 220,
    hp: 1000,
    attack: 20,
    attackSpeed: 1,
    armor: 0,
    atlasId: 'h',
    frameCount: 1,
  );
  final enemies = [
    for (var i = 0; i < count; i++)
      spawnFighter(
        world,
        side: 'enemy',
        x: 120 + i * 10,
        y: 220,
        hp: 1000,
        attack: 10,
        attackSpeed: 1,
        armor: 0,
        atlasId: 'e',
        frameCount: 1,
      ),
  ];
  final f = _Fight(world, combat, hero, enemies);
  f.stats(hero).cooldown = heroCooldown;
  for (final e in enemies) {
    f.stats(e).cooldown = enemyCooldown;
  }
  return f;
}

void main() {
  skillTests();
  rulesTests();
  group('parry', () {
    test(
      'a tap during the wind-up cancels that hit and starts the counter',
      () {
        final f = _fight(enemyCooldown: 0.8);
        final hits = <FighterHit>[];
        final parries = <AttackParried>[];
        f.world.events.on<FighterHit>(hits.add);
        f.world.events.on<AttackParried>(parries.add);

        f.world.step(
          0.4,
        ); // cooldown 0.4 <= windup 0.5: the wind-up has started
        expect(f.combat.tap(f.world), TapResult.parried);
        f.world.step(0.5); // the swing happens
        expect(hits.where((h) => h.attackerSide == 'enemy'), isEmpty);
        expect(f.hp(f.hero), 1000);
        expect(parries.single.attacker, f.enemy);
        expect(f.combat.counterLeft, greaterThan(0));
        expect(f.combat.ultimate, closeTo(0.34, 1e-9));
      },
    );

    test('the enemy attacks again normally after a parry', () {
      final f = _fight(enemyCooldown: 0.8);
      final hits = <FighterHit>[];
      f.world.events.on<FighterHit>(hits.add);
      f.world.step(0.4);
      f.combat.tap(f.world);
      for (var i = 0; i < 30; i++) {
        f.world.step(0.1);
      }
      expect(hits.where((h) => h.attackerSide == 'enemy'), isNotEmpty);
    });

    test('the counter bonus raises the hero damage while it lasts', () {
      final f = _fight(enemyCooldown: 0.8, heroCooldown: 1.0);
      final heroHits = <FighterHit>[];
      f.world.events.on<FighterHit>((h) {
        if (h.attackerSide == 'hero') heroHits.add(h);
      });
      f.world.step(0.4);
      f.combat.tap(f.world); // parry
      f.world.step(0.7); // the hero swings at t=1.0
      expect(heroHits.first.damage, closeTo(20 * 1.5, 1e-9));
    });

    test('a tap with no wind-up is a miss and locks tapping', () {
      final f = _fight();
      final missed = <TapMissed>[];
      f.world.events.on<TapMissed>(missed.add);
      expect(f.combat.tap(f.world), TapResult.missed);
      f.world.step(0.01);
      expect(missed, hasLength(1));
      expect(f.combat.tap(f.world), TapResult.locked);
      f.world.step(0.6); // past the 0.5 s lockout
      expect(f.combat.lockoutLeft, 0);
    });

    test('mashing cannot parry: a stray tap locks out the real window', () {
      final f = _fight(enemyCooldown: 1.0);
      f.world.step(0.3); // cooldown 0.7: no wind-up yet
      expect(f.combat.tap(f.world), TapResult.missed); // locked until t = 0.8
      f.world.step(0.25); // t = 0.55: the wind-up has started
      expect(f.combat.tap(f.world), TapResult.locked);
    });

    test('nothing happens unless timing is switched on', () {
      final f = _fight(enemyCooldown: 0.8, timing: false);
      f.world.step(0.4);
      expect(f.combat.tap(f.world), TapResult.none);
    });
  });

  group('timed strike', () {
    test('a tap just before the hero swings makes it a guaranteed crit', () {
      final f = _fight(heroCooldown: 0.5);
      final hits = <FighterHit>[];
      final strikes = <TimedStrike>[];
      f.world.events.on<FighterHit>(hits.add);
      f.world.events.on<TimedStrike>(strikes.add);
      f.world.step(0.3); // hero cooldown 0.2 <= window 0.25
      expect(f.combat.tap(f.world), TapResult.timedStrike);
      f.world.step(0.3);
      final h = hits.firstWhere((h) => h.attackerSide == 'hero');
      expect(h.critical, isTrue);
      expect(
        h.damage,
        closeTo(40, 1e-9),
      ); // attack 20 x timedStrikeMultiplier 2
      expect(strikes, hasLength(1));
      expect(f.combat.ultimate, greaterThan(0.2));
    });

    test('only the next swing is a timed strike', () {
      final f = _fight(heroCooldown: 0.5);
      final hits = <FighterHit>[];
      f.world.events.on<FighterHit>(hits.add);
      f.world.step(0.3);
      f.combat.tap(f.world);
      for (var i = 0; i < 25; i++) {
        f.world.step(0.1);
      }
      final heroHits = hits.where((h) => h.attackerSide == 'hero').toList();
      expect(heroHits.length, greaterThan(1));
      expect(heroHits[1].critical, isFalse);
    });

    test('a tap too early is a miss, not a strike', () {
      final f = _fight(heroCooldown: 5);
      expect(f.combat.tap(f.world), TapResult.missed);
    });
  });

  group('ultimate meter', () {
    test('hero hits fill it and spendUltimate empties it only when full', () {
      final f = _fight(heroCooldown: 0);
      for (var i = 0; i < 3; i++) {
        f.world.step(1.0);
      }
      expect(f.combat.ultimate, greaterThan(0));
      expect(f.combat.spendUltimate(), isFalse);
      f.combat.ultimate = 1;
      expect(f.combat.spendUltimate(), isTrue);
      expect(f.combat.ultimate, 0);
    });

    test('it never exceeds 1', () {
      final f = _fight(enemyCooldown: 0.8);
      f.combat.ultimate = 0.9;
      f.world.step(0.4);
      f.combat.tap(f.world);
      expect(f.combat.ultimate, 1);
    });
  });

  group('several enemies', () {
    test('enemies take turns: never two swings in the same instant', () {
      final f = _fight(count: 3, enemyCooldown: 0);
      final swings = <double>[];
      final attackers = <EntityId>{};
      var t = 0.0;
      f.world.events.on<FighterHit>((h) {
        if (h.attackerSide != 'enemy') return;
        attackers.add(h.attacker);
        swings.add(t);
      });
      for (var i = 0; i < 100; i++) {
        t += 0.05;
        f.world.step(0.05);
      }
      expect(attackers, f.enemies.toSet(), reason: 'everyone gets a turn');
      for (var i = 1; i < swings.length; i++) {
        expect(swings[i] - swings[i - 1], greaterThan(0.05));
      }
    });

    test('an enemy that dies while winding up does not block the others', () {
      final f = _fight(count: 2, enemyCooldown: 0.3);
      f.world.step(0.05);
      f.world.componentsOf<Health>().get(f.enemies[0])!.current = 0;
      var hits = 0;
      f.world.events.on<FighterHit>((h) {
        if (h.attackerSide == 'enemy') hits++;
      });
      for (var i = 0; i < 40; i++) {
        f.world.step(0.05);
      }
      expect(hits, greaterThan(0));
    });

    test('the hero hits the first enemy by default and the focus when set', () {
      final f = _fight(count: 3, heroCooldown: 0, enemyCooldown: 100);
      f.world.step(0.1);
      expect(f.hp(f.enemies[0]), lessThan(1000));
      expect(f.hp(f.enemies[1]), 1000);
      f.stats(f.hero).cooldown = 0;
      f.combat.focus = f.enemies[2];
      f.world.step(0.1);
      expect(f.hp(f.enemies[2]), lessThan(1000));
      expect(f.hp(f.enemies[1]), 1000);
    });

    test('a dead focus falls back to the next living enemy', () {
      final f = _fight(count: 2, heroCooldown: 0);
      f.combat.focus = f.enemies[1];
      f.world.componentsOf<Health>().get(f.enemies[1])!.current = 0;
      f.world.step(0.1);
      expect(f.hp(f.enemies[0]), lessThan(1000));
    });

    test('a dead enemy stops attacking', () {
      final f = _fight(count: 2, enemyCooldown: 0);
      f.world.componentsOf<Health>().get(f.enemies[0])!.current = 0;
      final attackers = <EntityId>{};
      f.world.events.on<FighterHit>((h) {
        if (h.attackerSide == 'enemy') attackers.add(h.attacker);
      });
      f.world.step(0.1);
      expect(attackers, {f.enemies[1]});
    });

    test('with one enemy the focus is irrelevant', () {
      final f = _fight(heroCooldown: 0);
      f.combat.focus = 9999;
      f.world.step(0.1);
      expect(f.hp(f.enemy), lessThan(1000));
    });
  });
}

class _Skills {
  _Skills(this.fight, List<HeroSkill> skills)
    : runner = SkillRunner(skills, fight.combat);
  final _Fight fight;
  final SkillRunner runner;

  bool use(HeroSkill s, {List<EntityId>? enemies}) => runner.use(
    fight.world,
    s,
    hero: fight.hero,
    enemy: fight.enemy,
    enemies: enemies ?? fight.enemies,
  );
}

void skillTests() {
  group('area and ultimate skills', () {
    const blast = HeroSkill(
      id: 'blast',
      label: 'Blast',
      kind: SkillKind.strike,
      power: 3,
      hitsAll: true,
    );
    const ult = HeroSkill(
      id: 'ult',
      label: 'Ult',
      kind: SkillKind.strike,
      power: 5,
      cooldown: 0,
      hitsAll: true,
      ultimate: true,
    );
    const single = HeroSkill(
      id: 'stab',
      label: 'Stab',
      kind: SkillKind.strike,
      power: 3,
    );

    test('an area strike hits every living enemy and only living ones', () {
      final f = _fight(count: 3);
      f.world.componentsOf<Health>().get(f.enemies[2])!.current = 0;
      final hits = <FighterHit>[];
      f.world.events.on<FighterHit>(hits.add);
      expect(_Skills(f, [blast]).use(blast), isTrue);
      f.world.step(0.01);
      expect(f.hp(f.enemies[0]), 1000 - 60);
      expect(f.hp(f.enemies[1]), 1000 - 60);
      expect(f.hp(f.enemies[2]), 0);
      expect(hits.where((h) => h.attackerSide == 'hero'), hasLength(2));
    });

    test('a normal strike still hits only the target', () {
      final f = _fight(count: 2);
      _Skills(f, [single]).use(single);
      expect(f.hp(f.enemies[0]), 1000 - 60);
      expect(f.hp(f.enemies[1]), 1000);
    });

    test(
      'an area strike with an empty list falls back to the single target',
      () {
        final f = _fight(count: 2);
        final s = _Skills(f, [blast]);
        expect(s.use(blast, enemies: const []), isTrue);
        expect(f.hp(f.enemies[0]), 1000 - 60);
        expect(f.hp(f.enemies[1]), 1000);
      },
    );

    test('an ultimate needs a full meter and empties it', () {
      final f = _fight(count: 2);
      final s = _Skills(f, [ult]);
      f.combat.ultimate = 0.9;
      expect(s.use(ult), isFalse);
      expect(f.hp(f.enemies[0]), 1000);
      f.combat.ultimate = 1;
      expect(s.use(ult), isTrue);
      expect(f.combat.ultimate, 0);
      expect(f.hp(f.enemies[1]), 1000 - 100);
    });

    test('an ultimate with no living target does not spend the meter', () {
      final f = _fight();
      f.world.componentsOf<Health>().get(f.enemy)!.current = 0;
      f.combat.ultimate = 1;
      expect(_Skills(f, [ult]).use(ult), isFalse);
      expect(f.combat.ultimate, 1);
    });
  });
}

void rulesTests() {
  group('rules', () {
    test('SquadRule adds extras by wave and never for bosses or treasure', () {
      const rule = SquadRule(oneExtraFromWave: 3, twoExtrasFromWave: 8);
      int n(int wave, {bool boss = false, WaveKind kind = WaveKind.normal}) =>
          rule.extrasFor(wave, boss: boss, kind: kind);
      expect(n(0), 0);
      expect(n(1), 0); // wave 2
      expect(n(2), 1); // wave 3
      expect(n(6), 1);
      expect(n(7), 2); // wave 8
      expect(n(9, boss: true), 0);
      expect(n(9, kind: WaveKind.treasure), 0);
      expect(n(9, kind: WaveKind.elite), 2);
    });

    test('SquadRule thresholds of 0 mean never', () {
      const rule = SquadRule(oneExtraFromWave: 0, twoExtrasFromWave: 0);
      expect(rule.extrasFor(50, boss: false, kind: WaveKind.normal), 0);
    });

    test('CombatTimingRules copies onto the system and switches timing on', () {
      final combat = AutoCombatSystem();
      expect(combat.playerTiming, isFalse);
      const CombatTimingRules(
        counterBonus: 3,
        missLockoutSeconds: 1,
        ultimateGainPerParry: 0.5,
      ).applyTo(combat);
      expect(combat.playerTiming, isTrue);
      expect(combat.counterBonus, 3);
      expect(combat.missLockoutSeconds, 1);
      expect(combat.ultimateGainPerParry, 0.5);
    });
  });
}
