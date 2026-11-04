import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' as eng;
import 'package:zarvan_platformer/zarvan_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_idle/zarvan_idle.dart';

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
  double atk = 10,
}) => spawnFighter(
  world,
  side: side,
  x: side == 'hero' ? 40 : 120,
  y: 200,
  hp: hp,
  attack: atk,
  attackSpeed: 100,
  armor: 0,
  atlasId: 'a',
  frameCount: 1,
  critChance: 0.3,
  critMultiplier: 2.5,
);

List<String> _texts(World world) {
  final s = world.componentsOf<eng.Text>();
  return [for (var i = 0; i < s.length; i++) s.denseAt(i).text];
}

const _strength = HeroUpgrade(
  id: 's',
  label: 'S',
  stat: 'attack',
  perLevel: 0.5,
  baseCost: 1,
);
const _vit = HeroUpgrade(
  id: 'v',
  label: 'V',
  stat: 'hp',
  perLevel: 1,
  baseCost: 1,
);

void main() {
  group('spawnWorldText', () {
    test('creates a centred world-space text at the given position', () {
      final world = _world();
      final id = spawnWorldText(
        world,
        12,
        34,
        'hi',
        fontSize: 6,
        colorArgb: 0xFF112233,
        zIndex: 9,
        maxWidth: 50,
      );
      final text = world.componentsOf<eng.Text>().get(id)!;
      expect(
        (text.text, text.fontSize, text.zIndex, text.maxWidth),
        ('hi', 6, 9, 50),
      );
      expect(text.screenSpace, isFalse);
      expect(text.align, eng.TextAlignment.center);
      final p = world.componentsOf<Position>().get(id)!;
      expect((p.x, p.y), (12, 34));
    });
  });

  group('HeroLoadout', () {
    test('derives stats from base values and bought levels', () {
      final progress = HeroProgress(coins: 100)
        ..buy(_strength)
        ..buy(_vit);
      final l = HeroLoadout(
        hp: 100,
        attack: 10,
        attackSpeed: 1,
        armor: 2,
        upgrades: const [_strength, _vit],
        progress: progress,
      );
      expect(
        (l.maxHp, l.attackNow, l.attackSpeedNow, l.armorNow),
        (200, 15, 1, 2),
      );
    });

    test(
      'apply updates a living hero, keeps its health fraction, crit and cooldown',
      () {
        final world = _world();
        final hero = _fighter(world, 'hero', hp: 100, atk: 10);
        world.componentsOf<Health>().get(hero)!.current = 50; // half health
        world.componentsOf<CombatStats>().get(hero)!.cooldown = 0.7;
        final progress = HeroProgress(coins: 100)..buy(_vit);
        HeroLoadout(
          hp: 100,
          attack: 10,
          attackSpeed: 100,
          armor: 0,
          upgrades: const [_strength, _vit],
          progress: progress,
        ).apply(world, hero);
        final h = world.componentsOf<Health>().get(hero)!;
        expect((h.max, h.current), (200, 100)); // still half
        final s = world.componentsOf<CombatStats>().get(hero)!;
        expect(
          (s.maxHp, s.cooldown, s.critChance, s.critMultiplier),
          (200, 0.7, 0.3, 2.5),
        );
      },
    );
  });

  group('ComboTracker', () {
    test('builds with consecutive hero hits, caps, and resets when hit', () {
      final world = _world();
      final combat = AutoCombatSystem();
      final combo = ComboTracker.install(
        world,
        combat,
        bonusPerHit: 0.1,
        maxHits: 3,
      );
      final hero = _fighter(world, 'hero');
      final enemy = _fighter(world, 'enemy');
      void hit(String side) {
        world.events.emit(
          FighterHit(
            attacker: side == 'hero' ? hero : enemy,
            defender: side == 'hero' ? enemy : hero,
            attackerSide: side,
            damage: 1,
            fatal: false,
          ),
        );
        world.events.flush();
      }

      expect(combo.multiplier, 1);
      hit('hero');
      expect(_texts(world), isNot(contains('Combo x1'))); // shown from the 2nd
      hit('hero');
      expect(_texts(world), contains('Combo x2'));
      expect(combat.damageFactor('hero'), closeTo(1.2, 1e-9));
      expect(combat.damageFactor('enemy'), 1);
      for (var i = 0; i < 5; i++) {
        hit('hero');
      }
      expect(combo.multiplier, closeTo(1.3, 1e-9)); // capped at 3 hits
      hit('enemy');
      expect(combo.count, 0);
      expect(_texts(world).any((t) => t.startsWith('Combo')), isFalse);
    });
  });

  group('WaveKind stats', () {
    const rw = RandomWaves(
      eliteHp: 2,
      eliteAttack: 1.5,
      eliteScale: 1.2,
      eliteCoins: 3,
      treasureHp: 4,
      treasureAttack: 0.1,
      treasureCoins: 8,
    );

    test('elites are tougher, larger and pay more; treasure is harmless', () {
      expect(WaveKind.elite.hpFactor(rw), 2);
      expect(WaveKind.elite.attackFactor(rw), 1.5);
      expect(WaveKind.elite.sizeFactor(rw), 1.2);
      expect(WaveKind.elite.coins(rw, 10), 30);
      expect(WaveKind.treasure.attackFactor(rw), 0.1);
      expect(WaveKind.treasure.coins(rw, 10), 80);
      expect(WaveKind.treasure.sizeFactor(rw), 1);
    });

    test('normal enemies and levels without random waves are unchanged', () {
      for (final k in WaveKind.values) {
        expect(k.hpFactor(null), 1);
        expect(k.attackFactor(null), 1);
        expect(k.sizeFactor(null), 1);
        expect(k.coins(null, 10), 10);
      }
      expect(WaveKind.normal.coins(rw, 10), 10);
    });

    test('labels', () {
      expect(WaveKind.normal.label('Wolf'), 'Wolf');
      expect(WaveKind.elite.label('Wolf'), 'Elite Wolf');
      expect(WaveKind.treasure.label('Stag'), 'Golden Stag');
    });
  });

  group('installSceneLights', () {
    test('spawns the sun and lights and a system that follows the hero', () {
      final world = _world();
      final hero = _fighter(world, 'hero');
      installSceneLights(
        world,
        sun: const SunLight(x: 100, y: 50, radius: 90),
        lights: const [
          SceneLight(anchor: LightAnchor.hero, x: 5, y: -10, radius: 30),
        ],
        heroOf: () => hero,
        enemyOf: () => null,
      );
      final lights = world.componentsOf<eng.Light2D>();
      expect(lights.length, 2);
      expect(world.systemOrder, contains('SceneLightSystem'));
      world.step(0.016);
      final pos = world.componentsOf<Position>();
      final follower = [
        for (var i = 0; i < lights.length; i++) lights.entityAt(i),
      ].firstWhere((e) => lights.get(e)!.radius <= 30.5);
      expect((pos.get(follower)!.x, pos.get(follower)!.y), (45, 190));
    });

    test('without a sun or lights it adds nothing', () {
      final world = _world();
      installSceneLights(world, heroOf: () => null, enemyOf: () => null);
      expect(world.componentsOf<eng.Light2D>().length, 0);
      expect(world.systemOrder, isNot(contains('SceneLightSystem')));
    });
  });
}
