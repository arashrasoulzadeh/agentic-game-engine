import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_idle/zarvan_idle.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart';

void main() {
  late World world;
  late EntityId hero, enemy;

  setUp(() {
    world = World(width: 180, height: 320);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);
    registerCombatComponents(world);
    world.addSystem(LungeSystem(minGap: 30, maxGap: 30));
    EntityId spawn(String side, double x) => spawnFighter(
      world,
      side: side,
      x: x,
      y: 200,
      hp: 100,
      attack: 1,
      attackSpeed: 1,
      armor: 0,
      atlasId: 'a',
      frameCount: 1,
    );
    hero = spawn('hero', 40);
    enemy = spawn('enemy', 140);
  });

  double x() => world.componentsOf<Position>().get(enemy)!.x;

  void windup() => world.events.emit(
    AttackWindup(attacker: enemy, attackerSide: 'enemy', seconds: 0.4),
  );

  test('a melee enemy runs to the hero, holds, and returns home', () {
    world.step(0.01);
    windup();
    world.step(0.01);
    world.step(0.15);
    expect(x(), 140, reason: 'waits while the wind-up runs, then dashes');
    world.step(0.1);
    expect(x(), inExclusiveRange(70, 140), reason: 'mid-dash');
    world.step(0.16);
    expect(x(), closeTo(70, 3), reason: 'arrives as the blow lands');
    world.step(0.1 + 0.2 + 0.05);
    expect(x(), 140, reason: 'back home');
    expect(world.componentsOf<Position>().get(hero)!.x, 40);
  });

  test('the stopping distance varies from lunge to lunge', () {
    final stops = <double>{};
    for (var n = 0; n < 6; n++) {
      final w = World(width: 180, height: 320);
      registerCoreComponents(w);
      registerFlutterComponents(w);
      registerPlatformerComponents(w);
      registerCombatComponents(w);
      w.addSystem(LungeSystem(minGap: 20, maxGap: 60));
      EntityId f(String side, double x) => spawnFighter(
        w,
        side: side,
        x: x,
        y: 200,
        hp: 100,
        attack: 1,
        attackSpeed: 1,
        armor: 0,
        atlasId: 'a',
        frameCount: 1,
      );
      f('hero', 40);
      final e = f('enemy', 140);
      w.step(0.01);
      w.events.emit(
        AttackWindup(attacker: e, attackerSide: 'enemy', seconds: 0.4),
      );
      w.step(0.01);
      w.step(0.4);
      final x = w.componentsOf<Position>().get(e)!.x;
      expect(x, inInclusiveRange(40 + 20 - 3, 40 + 60 + 3));
      stops.add(x.roundToDouble());
    }
    expect(stops.length, greaterThan(1));
  });

  test('an enemy with a volley power stays where it is', () {
    world.componentsOf<EnemyPowers>().set(enemy, EnemyPowers(volleyEvery: 3));
    world.step(0.01);
    windup();
    world.step(0.3);
    expect(x(), 140);
  });

  test('the hero never lunges', () {
    world.step(0.01);
    world.events.emit(
      AttackWindup(attacker: hero, attackerSide: 'hero', seconds: 0.4),
    );
    world.step(0.3);
    expect(world.componentsOf<Position>().get(hero)!.x, 40);
  });
}
