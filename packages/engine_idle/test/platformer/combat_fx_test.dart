import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_idle/engine_idle.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World buildWorld() {
  final world = World(width: 180, height: 320);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  registerCombatComponents(world);
  world
    ..addSystem(AutoCombatSystem())
    ..addSystem(AnimationSystem())
    ..addSystem(OneShotFxSystem());
  return world;
}

EntityId spawn(World world, String side, double x, {double hp = 1000}) =>
    spawnFighter(
      world,
      side: side,
      x: x,
      y: 100,
      hp: hp,
      attack: 50,
      attackSpeed: 0.05,
      armor: 0,
      atlasId: '${side}_idle',
      frameCount: 1,
    );

void main() {
  test('a hit spawns a spark; a fatal hit adds smoke; effects expire', () {
    final world = buildWorld();
    installCombatFx(
      world,
      const CombatFx(hit: FxClip('spark', 2), death: FxClip('smoke', 2)),
    );
    spawn(world, 'hero', 10);
    spawn(world, 'enemy', 10, hp: 5);
    world.step(0.01);
    // two sparks (both fighters hit) + one fatal smoke
    expect(world.storeOf<OneShotFx>().length, 3);
    for (var i = 0; i < 10; i++) {
      world.step(0.1);
    }
    expect(world.storeOf<OneShotFx>().length, 0);
  });

  test('effects sit on the defender silhouette, on the attacker side', () {
    final world = buildWorld();
    // 64px cell, 40px-tall figure standing on row 60, feet centred at x=32
    final table = PivotTable()
      ..register('enemy_idle', [const Pivot(32, 60, 20)], cell: 64);
    installCombatFx(
      world,
      const CombatFx(hit: FxClip('spark', 2)),
      pivots: table,
    );
    spawn(world, 'hero', 20);
    spawn(world, 'enemy', 120);
    world.step(0.01);

    final pos = world.storeOf<Position>();
    final fx = world.storeOf<OneShotFx>();
    var found = false;
    for (var i = 0; i < fx.length; i++) {
      final p = pos.get(fx.entityAt(i))!;
      if (p.x > 100 && p.x < 120) {
        found = true; // the hero's blow: left of the enemy's feet
        expect(p.y, lessThan(100 + (60 - 32.0)));
        expect(p.y, greaterThan(100 + (20 - 32.0)));
      }
    }
    expect(found, isTrue);
  });

  test('a hit bursts the defender emitter by CombatFx.hitBurst', () {
    final world = buildWorld();
    installCombatFx(world, const CombatFx(hitBurst: 7));
    final hero = spawn(world, 'hero', 10);
    final enemy = spawn(world, 'enemy', 100);
    world.storeOf<ParticleEmitter>()
      ..set(hero, ParticleEmitter())
      ..set(enemy, ParticleEmitter());
    world.step(0.01);
    expect(world.storeOf<ParticleEmitter>().get(hero)!.burstCount, 7);
    expect(world.storeOf<ParticleEmitter>().get(enemy)!.burstCount, 7);
  });

  test('spawnFighter attaches the impact emitter it is given', () {
    final world = buildWorld();
    final e = spawnFighter(
      world,
      side: 'hero',
      x: 0,
      y: 0,
      hp: 1,
      attack: 1,
      attackSpeed: 1,
      armor: 0,
      atlasId: 'h',
      frameCount: 1,
      impactParticles: ParticleEmitter(colorArgb: 0xFFFFD27A),
    );
    expect(world.storeOf<ParticleEmitter>().get(e)!.colorArgb, 0xFFFFD27A);
  });
}
