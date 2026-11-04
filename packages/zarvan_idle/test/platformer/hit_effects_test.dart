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
  return world;
}

EntityId _fighter(
  World world,
  String side,
  double x, {
  double hp = 100,
  double attack = 10,
  double critChance = 0,
  double critMultiplier = 2,
}) => spawnFighter(
  world,
  side: side,
  x: x,
  y: 200,
  hp: hp,
  attack: attack,
  attackSpeed: 100,
  armor: 0,
  atlasId: 'a',
  frameCount: 1,
  critChance: critChance,
  critMultiplier: critMultiplier,
);

List<String> _texts(World world) {
  final store = world.componentsOf<eng.Text>();
  return [for (var i = 0; i < store.length; i++) store.denseAt(i).text];
}

void main() {
  group('critical hits', () {
    test('a guaranteed crit multiplies damage and flags the event', () {
      final world = _world()..addSystem(AutoCombatSystem());
      final hits = <FighterHit>[];
      world.events.on<FighterHit>(hits.add);
      _fighter(world, 'hero', 40, attack: 10, critChance: 1, critMultiplier: 2);
      final enemy = _fighter(world, 'enemy', 120, attack: 1);
      world.step(0.01);
      final heroHit = hits.firstWhere((h) => h.attackerSide == 'hero');
      expect(heroHit.critical, isTrue);
      expect(heroHit.damage, 20);
      expect(world.componentsOf<Health>().get(enemy)!.current, 80);
    });

    test('critChance 0 never crits', () {
      final world = _world()..addSystem(AutoCombatSystem());
      final hits = <FighterHit>[];
      world.events.on<FighterHit>(hits.add);
      _fighter(world, 'hero', 40, attack: 10);
      _fighter(world, 'enemy', 120, attack: 1);
      world.step(0.01);
      expect(hits.every((h) => !h.critical), isTrue);
      expect(hits.firstWhere((h) => h.attackerSide == 'hero').damage, 10);
    });

    test('copyWith changes only what is named and keeps crit and cooldown', () {
      final s = CombatStats(
        maxHp: 10,
        attack: 2,
        attackSpeed: 1,
        armor: 0,
        cooldown: 0.4,
        critChance: 0.25,
        critMultiplier: 3,
      );
      final c = s.copyWith(attack: 5);
      expect(c.attack, 5);
      expect(
        (
          c.maxHp,
          c.attackSpeed,
          c.armor,
          c.cooldown,
          c.critChance,
          c.critMultiplier,
        ),
        (10, 1, 0, 0.4, 0.25, 3),
      );
    });

    test(
      'registerWaveCombatComponents registers every wave-combat component',
      () {
        final world = World(width: 1, height: 1);
        registerCoreComponents(world);
        eng.registerFlutterComponents(world);
        registerWaveCombatComponents(world);
        registerWaveCombatComponents(world); // idempotent
        for (final name in [
          'combatRole',
          'combatStats',
          'enemyPowers',
          'damageNumber',
          'hitRecoil',
          'screenFlash',
          'windupTint',
        ]) {
          expect(world.components.isRegistered(name), isTrue, reason: name);
        }
      },
    );

    test('CombatStats keeps its crit values through JSON', () {
      final s = CombatStats(
        maxHp: 1,
        attack: 2,
        attackSpeed: 1,
        armor: 0,
        critChance: 0.25,
        critMultiplier: 3,
      );
      final back = CombatStats.fromJson(s.toJson());
      expect((back.critChance, back.critMultiplier), (0.25, 3));
    });
  });

  group('damage numbers', () {
    test(
      'a hit spawns a number over the target; crits are bigger and end in !',
      () {
        final world = _world();
        installDamageNumbers(world, const DamageNumberStyle());
        final hero = _fighter(world, 'hero', 40);
        final enemy = _fighter(world, 'enemy', 120, hp: 100);
        world.events.emit(
          FighterHit(
            attacker: hero,
            defender: enemy,
            attackerSide: 'hero',
            damage: 12,
            fatal: false,
          ),
        );
        world.events.emit(
          FighterHit(
            attacker: hero,
            defender: enemy,
            attackerSide: 'hero',
            damage: 24,
            fatal: false,
            critical: true,
          ),
        );
        world.events.flush();
        expect(_texts(world), containsAll(['12', '24!']));
        final store = world.componentsOf<eng.Text>();
        double sizeOf(String t) => [
          for (var i = 0; i < store.length; i++) store.denseAt(i),
        ].firstWhere((x) => x.text == t).fontSize;
        expect(sizeOf('24!'), greaterThan(sizeOf('12')));
      },
    );

    test('numbers rise, fade and are removed after their lifetime', () {
      final world = _world();
      final style = const DamageNumberStyle(lifetime: 1);
      installDamageNumbers(world, style);
      world.addSystem(DamageNumberSystem());
      final hero = _fighter(world, 'hero', 40);
      final enemy = _fighter(world, 'enemy', 120);
      world.events.emit(
        FighterHit(
          attacker: hero,
          defender: enemy,
          attackerSide: 'hero',
          damage: 5,
          fatal: false,
        ),
      );
      world.events.flush();
      final numbers = world.componentsOf<DamageNumber>();
      final id = numbers.entityAt(1); // the coloured one (the copy is first)
      final y0 = world.componentsOf<Position>().get(id)!.y;
      world.step(0.75);
      expect(world.componentsOf<Position>().get(id)!.y, lessThan(y0));
      final alpha = world.componentsOf<eng.Text>().get(id)!.colorArgb >>> 24;
      expect(alpha, lessThan(255));
      world.step(0.5);
      expect(numbers.length, 0);
      expect(_texts(world).contains('5'), isFalse);
      expect(world.componentsOf<eng.Text>().length, lessThan(8));
    });

    test('enemy hits on the hero use the hit-the-hero colour', () {
      final world = _world();
      installDamageNumbers(world, const DamageNumberStyle());
      final hero = _fighter(world, 'hero', 40);
      final enemy = _fighter(world, 'enemy', 120);
      world.events.emit(
        FighterHit(
          attacker: enemy,
          defender: hero,
          attackerSide: 'enemy',
          damage: 3,
          fatal: false,
        ),
      );
      world.events.flush();
      final t = world.componentsOf<eng.Text>();
      final colors = [
        for (var i = 0; i < t.length; i++)
          if (t.denseAt(i).text == '3') t.denseAt(i).colorArgb,
      ];
      expect(
        colors,
        containsAll([
          const DamageNumberStyle().enemyHitColorArgb,
          const DamageNumberStyle().shadowColorArgb,
        ]),
      );
    });
  });

  group('damage number style', () {
    test('hero hits get hotter colours as they get heavier', () {
      const s = DamageNumberStyle();
      final colors = [
        for (final f in [0.01, 0.1, 0.3, 0.9]) s.tierColor(f),
      ];
      expect(colors.toSet().length, 4);
      expect(colors.first, 0xFFFFFFFF);
      expect(colors.last, 0xFFFF4D2E);
    });

    test('a new number pops larger and settles to normal size', () {
      final world = _world();
      installDamageNumbers(world, const DamageNumberStyle());
      world.addSystem(DamageNumberSystem());
      final hero = _fighter(world, 'hero', 40);
      final enemy = _fighter(world, 'enemy', 120);
      world.events.emit(
        FighterHit(
          attacker: hero,
          defender: enemy,
          attackerSide: 'hero',
          damage: 5,
          fatal: false,
        ),
      );
      world.events.flush();
      final id = world.componentsOf<DamageNumber>().entityAt(1);
      world.step(0.01);
      expect(
        world.componentsOf<eng.Text>().get(id)!.textScale,
        greaterThan(1.4),
      );
      world.step(0.3);
      expect(world.componentsOf<eng.Text>().get(id)!.textScale, 1);
    });

    test('criticals are larger, gold and pop harder than ordinary hits', () {
      final world = _world();
      installDamageNumbers(world, const DamageNumberStyle());
      final hero = _fighter(world, 'hero', 40);
      final enemy = _fighter(world, 'enemy', 120);
      for (final crit in [false, true]) {
        world.events.emit(
          FighterHit(
            attacker: hero,
            defender: enemy,
            attackerSide: 'hero',
            damage: 10,
            fatal: false,
            critical: crit,
          ),
        );
      }
      world.events.flush();
      final store = world.componentsOf<eng.Text>();
      final plain = [
        for (var i = 0; i < store.length; i++) store.denseAt(i),
      ].firstWhere((x) => x.text == '10' && x.colorArgb != 0xFF1A0B00);
      final crit = [
        for (var i = 0; i < store.length; i++) store.denseAt(i),
      ].firstWhere((x) => x.text == '10!' && x.colorArgb != 0xFF1A0B00);
      expect(crit.fontSize, greaterThan(plain.fontSize));
      expect(crit.colorArgb, const DamageNumberStyle().criticalColorArgb);
    });
  });

  group('hit feedback', () {
    test('the defender is knocked away from the attacker and springs back', () {
      final world = _world()..addSystem(HitFeedbackSystem());
      installHitFeedback(world, const HitFeedback(), eng.Camera());
      final hero = _fighter(world, 'hero', 40);
      final enemy = _fighter(world, 'enemy', 120);
      world.events.emit(
        FighterHit(
          attacker: hero,
          defender: enemy,
          attackerSide: 'hero',
          damage: 5,
          fatal: false,
        ),
      );
      world.events.flush();
      expect(world.componentsOf<HitRecoil>().has(enemy), isTrue);
      world.step(0.04);
      expect(
        world.componentsOf<eng.Sprite>().get(enemy)!.offsetX,
        greaterThan(0),
      );
      world.step(0.5);
      expect(world.componentsOf<eng.Sprite>().get(enemy)!.offsetX, 0);
      expect(world.componentsOf<HitRecoil>().has(enemy), isFalse);
    });

    test(
      'a hit on the hero flashes the screen red; a hit on an enemy does not',
      () {
        final world = _world()..addSystem(HitFeedbackSystem());
        installHitFeedback(world, const HitFeedback(), eng.Camera());
        final hero = _fighter(world, 'hero', 40);
        final enemy = _fighter(world, 'enemy', 120);
        int alpha() {
          final tints = world.componentsOf<eng.ScreenTint>();
          return tints.denseAt(0).colorArgb >>> 24;
        }

        world.events.emit(
          FighterHit(
            attacker: hero,
            defender: enemy,
            attackerSide: 'hero',
            damage: 5,
            fatal: false,
          ),
        );
        world.events.flush();
        world.step(0.01);
        expect(alpha(), 0);

        world.events.emit(
          FighterHit(
            attacker: enemy,
            defender: hero,
            attackerSide: 'enemy',
            damage: 5,
            fatal: false,
          ),
        );
        world.events.flush();
        world.step(0.01);
        expect(alpha(), greaterThan(40));
        world.step(0.5);
        expect(alpha(), 0);
      },
    );

    test('a critical shakes the camera harder than an ordinary enemy hit', () {
      final camera = eng.Camera();
      final world = _world();
      installHitFeedback(world, const HitFeedback(), camera);
      final hero = _fighter(world, 'hero', 40);
      final enemy = _fighter(world, 'enemy', 120);
      world.events.emit(
        FighterHit(
          attacker: hero,
          defender: enemy,
          attackerSide: 'hero',
          damage: 5,
          fatal: false,
        ),
      );
      world.events.flush();
      camera.update(0.02);
      expect(camera.shakeOffset, Offset.zero); // an ordinary hero hit: no shake
      world.events.emit(
        FighterHit(
          attacker: hero,
          defender: enemy,
          attackerSide: 'hero',
          damage: 10,
          fatal: false,
          critical: true,
        ),
      );
      world.events.flush();
      camera.update(0.02);
      expect(camera.shakeOffset, isNot(Offset.zero));
    });
  });

  group('early-game ramp', () {
    LevelData level(Map<String, dynamic> extra) => LevelData.fromJson({
      'name': 'L',
      'wave': ['a'],
      'boss': 'b',
      'background': 'x',
      'hero': {'x': 1, 'y': 2},
      'enemy_anchor': {'x': 3, 'y': 4},
      ...extra,
    });

    test('no ramp by default', () {
      expect(level({}).enemyRamp(0), 1);
      expect(level({}).enemyRamp(50), 1);
    });

    test('enemies start at the ramp start and reach full strength', () {
      final l = level({
        'enemy_ramp': {'start': 0.5, 'waves': 4},
      });
      expect(l.enemyRamp(0), 0.5);
      expect(l.enemyRamp(2), 0.75);
      expect(l.enemyRamp(4), 1);
      expect(l.enemyRamp(10), 1);
    });

    test('hero crit values are read from the level', () {
      final l = level({
        'hero_crit': {'chance': 0.2, 'multiplier': 2.0},
      });
      expect((l.heroCritChance, l.heroCritMultiplier), (0.2, 2.0));
      expect(level({}).heroCritChance, 0);
    });
  });
}
