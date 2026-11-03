import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_idle/zarvan_idle.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World buildWorld([AutoCombatSystem? combat]) {
  final world = World(width: 180, height: 320);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  registerCombatComponents(world);
  world
    ..addSystem(combat ?? AutoCombatSystem())
    ..addSystem(HitFlashSystem())
    ..addSystem(FighterDeathSystem())
    ..addSystem(SpriteStateSystem())
    ..addSystem(AnimationSystem());
  return world;
}

EntityId fighter(
  World world,
  String side, {
  double hp = 100,
  double attack = 1,
  double x = 40,
}) => spawnFighter(
  world,
  side: side,
  x: x,
  y: 200,
  hp: hp,
  attack: attack,
  attackSpeed: 1,
  armor: 0,
  atlasId: '${side}_idle',
  frameCount: 4,
  extraClips: {
    'attack': SpriteClip(atlasId: '${side}_attack', frames: 4),
    'death': SpriteClip(atlasId: '${side}_death', frames: 3),
  },
);

void main() {
  test('swinging plays the attack sheet, then returns to idle', () {
    final world = buildWorld();
    final hero = fighter(world, 'hero');
    fighter(world, 'enemy', x: 120);
    world.step(0.01);
    expect(world.componentsOf<Sprite>().get(hero)!.atlasId, 'hero_attack');
    for (var i = 0; i < 6; i++) {
      world.step(0.1);
    }
    expect(world.componentsOf<SpriteStates>().get(hero)!.current, 'idle');
  });

  test('a fighter whose health runs out plays death and stays down', () {
    final world = buildWorld();
    fighter(world, 'hero', attack: 500);
    final enemy = fighter(world, 'enemy', hp: 10, x: 120);
    world.step(0.01);
    expect(world.componentsOf<Sprite>().get(enemy)!.atlasId, 'enemy_death');
    expect(spriteStateFinished(world, enemy, 'death'), isFalse);
    for (var i = 0; i < 10; i++) {
      world.step(0.2);
    }
    expect(spriteStateFinished(world, enemy, 'death'), isTrue);
    expect(world.componentsOf<Sprite>().get(enemy)!.region, '2');
  });

  test('AutoCombatSystem.enabled = false holds fire', () {
    final combat = AutoCombatSystem()..enabled = false;
    final world = buildWorld(combat);
    final hero = fighter(world, 'hero', attack: 500);
    final enemy = fighter(world, 'enemy', hp: 10, x: 120);
    world.step(0.5);
    expect(world.componentsOf<Health>().get(enemy)!.current, 10);
    expect(world.componentsOf<SpriteStates>().get(hero)!.current, 'idle');
    combat.enabled = true;
    world.step(0.1);
    expect(world.componentsOf<Health>().get(enemy)!.current, 0);
  });
}
