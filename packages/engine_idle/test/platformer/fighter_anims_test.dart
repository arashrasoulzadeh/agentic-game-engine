import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_idle/engine_idle.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late World world;
  setUp(() {
    world = World(width: 180, height: 320);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);
    registerCombatComponents(world);
    world
      ..addSystem(AutoCombatSystem())
      ..addSystem(HitFlashSystem())
      ..addSystem(FighterAnimationSystem())
      ..addSystem(AnimationSystem());
  });

  EntityId fighter(String side, {double hp = 100, double attack = 1}) =>
      spawnFighter(
        world,
        side: side,
        x: 40,
        y: 200,
        hp: hp,
        attack: attack,
        attackSpeed: 1,
        armor: 0,
        atlasId: '${side}_idle',
        frameCount: 4,
        extraClips: {
          'attack': FighterClip(atlasId: '${side}_attack', frames: 4),
          'death': FighterClip(atlasId: '${side}_death', frames: 3),
        },
      );

  test('attacking swaps to the attack sheet, then returns to idle', () {
    final hero = fighter('hero');
    fighter('enemy');
    world.step(0.01);
    expect(world.storeOf<Sprite>().get(hero)!.atlasId, 'hero_attack');
    expect(world.storeOf<FighterAnims>().get(hero)!.current, 'attack');

    for (var i = 0; i < 6; i++) {
      world.step(0.1);
    }
    expect(world.storeOf<FighterAnims>().get(hero)!.current, 'idle');
    expect(world.storeOf<Sprite>().get(hero)!.atlasId, 'hero_idle');
  });

  test('death plays to the last frame and holds', () {
    fighter('hero', attack: 500);
    final enemy = fighter('enemy', hp: 10);
    world.step(0.01);
    expect(fighterDeathFinished(world, enemy), isFalse);
    expect(world.storeOf<Sprite>().get(enemy)!.atlasId, 'enemy_death');

    for (var i = 0; i < 10; i++) {
      world.step(0.2);
    }
    expect(fighterDeathFinished(world, enemy), isTrue);
    expect(world.storeOf<Sprite>().get(enemy)!.region, '2');
  });

  test('a dead fighter ignores later animation requests', () {
    fighter('hero', attack: 500);
    final enemy = fighter('enemy', hp: 10);
    world.step(0.01);
    playFighterAnim(world, enemy, 'attack');
    world.step(0.5);
    expect(world.storeOf<FighterAnims>().get(enemy)!.current, 'death');
  });
}
