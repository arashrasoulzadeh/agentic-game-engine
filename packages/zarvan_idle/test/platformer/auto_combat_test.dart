import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_platformer/zarvan_platformer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_idle/zarvan_idle.dart';

void main() {
  World build() {
    final world = World(width: 180, height: 320);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);
    registerCombatComponents(world);
    world.addSystem(AutoCombatSystem());
    world.addSystem(HitFlashSystem());
    world.addSystem(AnimationSystem());
    return world;
  }

  test('AutoCombatSystem damages the opposing fighter via Health', () {
    final world = build();
    spawnFighter(
      world,
      side: 'hero',
      x: 40,
      y: 220,
      hp: 100,
      attack: 20,
      attackSpeed: 10,
      armor: 0,
      atlasId: 'hero_idle',
      frameCount: 4,
    );
    final enemy = spawnFighter(
      world,
      side: 'enemy',
      x: 120,
      y: 220,
      hp: 50,
      attack: 1,
      attackSpeed: 0.1,
      armor: 0,
      atlasId: 'wolf_idle',
      frameCount: 4,
    );

    for (var i = 0; i < 20; i++) {
      world.step(0.1);
    }
    expect(world.componentsOf<Health>().get(enemy)!.current, lessThan(50));
  });

  test('hit uses engine flashHit / HitFlashSystem for red tint', () {
    final world = build();
    final hero = spawnFighter(
      world,
      side: 'hero',
      x: 40,
      y: 220,
      hp: 100,
      attack: 50,
      attackSpeed: 100,
      armor: 0,
      atlasId: 'hero_idle',
      frameCount: 4,
    );
    final enemy = spawnFighter(
      world,
      side: 'enemy',
      x: 120,
      y: 220,
      hp: 500,
      attack: 50,
      attackSpeed: 100,
      armor: 0,
      atlasId: 'wolf_idle',
      frameCount: 4,
    );

    world.step(0.05);
    expect(
      world.componentsOf<Sprite>().get(enemy)!.tintArgb,
      kDefaultHitFlashTint,
    );
    expect(
      world.componentsOf<Sprite>().get(hero)!.tintArgb,
      kDefaultHitFlashTint,
    );

    world.componentsOf<HitFlash>().get(enemy)!.remaining = 0;
    world.componentsOf<HitFlash>().get(hero)!.remaining = 0;
    world.step(0.01);
    expect(world.componentsOf<Sprite>().get(enemy)!.tintArgb, isNull);
    expect(world.componentsOf<Sprite>().get(hero)!.tintArgb, isNull);
  });
}
