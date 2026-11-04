import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' as eng;
import 'package:zarvan_platformer/zarvan_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_idle/zarvan_idle.dart';

World _world() {
  final world = World(width: 180, height: 320);
  registerCoreComponents(world);
  eng.registerFlutterComponents(world);
  registerPlatformerComponents(world);
  registerCombatComponents(world);
  registerDamageNumberComponents(world);
  registerHitFeedbackComponents(world);
  registerWindupComponents(world);
  return world;
}

EntityId _fighter(
  World world,
  String side,
  double x, {
  double hp = 100,
  double attack = 10,
  double speed = 1,
  EnemyPowers? powers,
}) => spawnFighter(
  world,
  side: side,
  x: x,
  y: 200,
  hp: hp,
  attack: attack,
  attackSpeed: speed,
  armor: 0,
  atlasId: 'a',
  frameCount: 1,
  powers: powers,
);

LevelData _level(Map<String, dynamic> extra, {List<String>? wave}) =>
    LevelData.fromJson({
      'name': 'L',
      'wave': wave ?? ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'],
      'boss': 'boss',
      'background': 'x',
      'hero': {'x': 1, 'y': 2},
      'enemy_anchor': {'x': 3, 'y': 4},
      ...extra,
    });

void main() {
  group('EnemyPowers.parse', () {
    test('reads rage, dodge and first-strike texts from sidecar effects', () {
      final p = EnemyPowers.parse([
        '+30% attack speed below 50% hp',
        '25% chance to dodge each hero attack',
        'first strike each wave deals +50% damage',
        'immune to stun',
      ])!;
      expect(p.rageAttackSpeed, closeTo(1.3, 1e-9));
      expect(p.rageBelowHp, 0.5);
      expect(p.dodge, 0.25);
      expect(p.firstStrike, 1.5);
      expect(p.rageActive(0.4), isTrue);
      expect(p.rageActive(0.6), isFalse);
    });

    test('reads attack rage and the first-attack phrasing', () {
      final p = EnemyPowers.parse([
        '+25% attack below 30% hp',
        'first attack deals 200% damage and knocks back',
      ])!;
      expect((p.rageAttack, p.rageBelowHp, p.firstStrike), (1.25, 0.3, 2.0));
    });

    test('nothing recognisable gives null; JSON round-trips', () {
      expect(EnemyPowers.parse(['immune to stun']), isNull);
      expect(EnemyPowers.parse([]), isNull);
      final p = EnemyPowers.parse(['25% chance to dodge'])!;
      expect(EnemyPowers.fromJson(p.toJson()).dodge, 0.25);
    });

    test('FighterStats collects powers and boss phases', () {
      final s = FighterStats.fromJson({
        'stats': {'hp': 10, 'attack': 1},
        'powers': [
          {'effect': '25% chance to dodge each hero attack'},
        ],
        'phases': [
          {'hp_below': 50, 'effect': 'attack_speed x1.5'},
        ],
      });
      final p = EnemyPowers.parse(s.powers)!;
      expect(p.dodge, 0.25);
      expect(p.rageAttackSpeed, closeTo(1.5, 1e-9));
      expect(p.rageBelowHp, 0.5);
    });
  });

  group('powers in combat', () {
    test('a first strike deals bonus damage once', () {
      final world = _world()..addSystem(AutoCombatSystem());
      final hits = <FighterHit>[];
      world.events.on<FighterHit>(hits.add);
      final hero = _fighter(world, 'hero', 40, hp: 1000, attack: 1, speed: 1);
      _fighter(
        world,
        'enemy',
        120,
        attack: 10,
        speed: 2,
        powers: EnemyPowers(firstStrike: 3),
      );
      world.step(0.01);
      world.step(0.6);
      world.step(0.6);
      final enemyHits = hits.where((h) => h.attackerSide == 'enemy').toList();
      expect(enemyHits.length, greaterThanOrEqualTo(2));
      expect(enemyHits.first.damage, 30);
      expect(enemyHits[1].damage, 10);
      expect(world.componentsOf<Health>().get(hero)!.current, lessThan(1000));
    });

    test('a guaranteed dodge avoids damage and emits FighterDodge', () {
      final world = _world()..addSystem(AutoCombatSystem());
      final dodges = <FighterDodge>[];
      world.events.on<FighterDodge>(dodges.add);
      _fighter(world, 'hero', 40, attack: 50, speed: 5);
      final enemy = _fighter(
        world,
        'enemy',
        120,
        attack: 0,
        powers: EnemyPowers(dodge: 1),
      );
      world.step(0.01);
      world.step(0.3);
      expect(dodges, isNotEmpty);
      expect(world.componentsOf<Health>().get(enemy)!.current, 100);
    });

    test('rage speeds the attacker up below its health threshold', () {
      int hitsIn(double enemyHp) {
        final world = _world()..addSystem(AutoCombatSystem());
        var n = 0;
        world.events.on<FighterHit>((h) {
          if (h.attackerSide == 'enemy') n++;
        });
        _fighter(world, 'hero', 40, hp: 1e6, attack: 0.01, speed: 0.05);
        _fighter(
          world,
          'enemy',
          120,
          hp: 100,
          attack: 1,
          speed: 1,
          powers: EnemyPowers(rageBelowHp: 0.5, rageAttackSpeed: 3),
        );
        world
                .componentsOf<Health>()
                .get(world.componentsOf<Health>().entityAt(1))!
                .current =
            enemyHp;
        for (var i = 0; i < 60; i++) {
          world.step(0.1);
        }
        return n;
      }

      expect(hitsIn(20), greaterThan(hitsIn(100) * 2));
    });

    test('a windup is announced once before each attack', () {
      final world = _world()
        ..addSystem(AutoCombatSystem()..windupSeconds = 0.3);
      final windups = <AttackWindup>[];
      world.events.on<AttackWindup>(windups.add);
      _fighter(world, 'hero', 40, hp: 1e6, attack: 0.01, speed: 0.05);
      _fighter(world, 'enemy', 120, hp: 1e6, attack: 1, speed: 1);
      for (var i = 0; i < 35; i++) {
        world.step(0.1);
      }
      final enemy = windups.where((w) => w.attackerSide == 'enemy').toList();
      expect(enemy.length, inInclusiveRange(2, 4));
      expect(enemy.first.seconds, lessThanOrEqualTo(0.3));
    });

    test('a damage multiplier scales one side only', () {
      final world = _world()
        ..addSystem(
          AutoCombatSystem()
            ..damageModifiers.add((side) => side == 'hero' ? 2.0 : 1.0),
        );
      final hits = <FighterHit>[];
      world.events.on<FighterHit>(hits.add);
      _fighter(world, 'hero', 40, attack: 10);
      _fighter(world, 'enemy', 120, attack: 10);
      world.step(0.01);
      expect(hits.firstWhere((h) => h.attackerSide == 'hero').damage, 20);
      expect(hits.firstWhere((h) => h.attackerSide == 'enemy').damage, 10);
    });
  });

  group('windup telegraph and hit-stop', () {
    test('a winding-up enemy glows and shows a warning; the tint clears', () {
      final world = _world()..addSystem(HitFeedbackSystem());
      world.addSystem(DamageNumberSystem());
      installHitFeedback(world, const HitFeedback(), eng.Camera());
      final enemy = _fighter(world, 'enemy', 120);
      world.events.emit(
        AttackWindup(attacker: enemy, attackerSide: 'enemy', seconds: 0.3),
      );
      world.events.flush();
      expect(
        world.componentsOf<eng.Sprite>().get(enemy)!.tintArgb,
        const HitFeedback().windupTintArgb,
      );
      final texts = world.componentsOf<eng.Text>();
      expect([
        for (var i = 0; i < texts.length; i++) texts.denseAt(i).text,
      ], contains('!'));
      world.step(0.4);
      expect(world.componentsOf<eng.Sprite>().get(enemy)!.tintArgb, isNull);
    });

    test('the hero attacking does not telegraph', () {
      final world = _world()..addSystem(HitFeedbackSystem());
      installHitFeedback(world, const HitFeedback(), eng.Camera());
      final hero = _fighter(world, 'hero', 40);
      world.events.emit(
        AttackWindup(attacker: hero, attackerSide: 'hero', seconds: 0.3),
      );
      world.events.flush();
      expect(world.componentsOf<eng.Sprite>().get(hero)!.tintArgb, isNull);
    });

    test('hit-stop freezes the world clock for real seconds, then resumes', () {
      final world = _world()..addSystem(AutoCombatSystem());
      final stop = HitStop(world);
      expect(stop.frozen, isFalse);
      stop.freeze(0.1);
      expect(stop.frozen, isTrue);
      expect(world.isHitStopped, isTrue);
      world.step(0.06);
      expect(stop.frozen, isTrue);
      world.step(0.06);
      expect(stop.frozen, isFalse);
    });

    test('a critical hit triggers the freeze; a light hit does not', () {
      final world = _world()..addSystem(AutoCombatSystem());
      final stop = HitStop(world);
      installHitFeedback(
        world,
        const HitFeedback(),
        eng.Camera(),
        hitStop: stop,
      );
      final hero = _fighter(world, 'hero', 40);
      final enemy = _fighter(world, 'enemy', 120, hp: 1000);
      FighterHit hit(double dmg, {bool crit = false}) => FighterHit(
        attacker: hero,
        defender: enemy,
        attackerSide: 'hero',
        damage: dmg,
        fatal: false,
        critical: crit,
      );
      world.events.emit(hit(5));
      world.events.flush();
      expect(stop.frozen, isFalse);
      world.events.emit(hit(5, crit: true));
      world.events.flush();
      expect(stop.frozen, isTrue);
    });
  });

  group('random waves', () {
    final rw = {
      'random_waves': {
        'elite_chance': 1.0,
        'treasure_chance': 1.0,
        'treasure_enemy': 'gold',
        'shuffle_block': 4,
      },
    };

    test('without random_waves the order is untouched and all normal', () {
      final plan = WavePlan.generate(_level({}), math.Random(1));
      expect(plan.ids, _level({}).wave);
      expect(plan.kinds.every((k) => k == WaveKind.normal), isTrue);
    });

    test('the first wave is always plain; others can be elite', () {
      final plan = WavePlan.generate(_level(rw), math.Random(3));
      expect(plan.kinds.first, WaveKind.normal);
      expect(plan.kinds.skip(1).where((k) => k != WaveKind.normal), isNotEmpty);
    });

    test(
      'exactly one treasure enemy appears, with its own art, never first',
      () {
        final plan = WavePlan.generate(_level(rw), math.Random(7));
        final t = [
          for (var i = 0; i < plan.ids.length; i++)
            if (plan.kinds[i] == WaveKind.treasure) i,
        ];
        expect(t.length, 1);
        expect(t.single, greaterThan(0));
        expect(plan.ids[t.single], 'gold');
      },
    );

    test('shuffling stays inside blocks so the difficulty curve is kept', () {
      final lv = _level({
        'random_waves': {'shuffle_block': 4},
      });
      final plan = WavePlan.generate(lv, math.Random(5));
      expect(plan.ids.sublist(0, 4).toSet(), {'a', 'b', 'c', 'd'});
      expect(plan.ids.sublist(4).toSet(), {'e', 'f', 'g', 'h'});
    });

    test('different seeds give different runs; the same seed repeats', () {
      final lv = _level({
        'random_waves': {'elite_chance': 0.5, 'shuffle_block': 8},
      });
      final a = WavePlan.generate(lv, math.Random(1));
      final b = WavePlan.generate(lv, math.Random(1));
      final c = WavePlan.generate(lv, math.Random(2));
      expect(a.ids, b.ids);
      expect(a.kinds, b.kinds);
      expect(
        a.ids.join() + a.kinds.join(),
        isNot(c.ids.join() + c.kinds.join()),
      );
    });

    test(
      'the treasure art is loaded with the level and counts as an enemy',
      () {
        expect(_level(rw).enemyIds, contains('gold'));
      },
    );

    test('a level without a treasure enemy never makes one', () {
      final lv = _level({
        'random_waves': {'treasure_chance': 1.0, 'elite_chance': 0.0},
      });
      final plan = WavePlan.generate(lv, math.Random(9));
      expect(plan.kinds.contains(WaveKind.treasure), isFalse);
    });
  });
}
