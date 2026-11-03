import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  World build() {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(HitFlashSystem());
    return world;
  }

  test('HitFlash round-trips and registerFlutterComponents registers it', () {
    final world = build();
    expect(world.components.isRegistered('hitFlash'), isTrue);
    final decoded = HitFlash.fromJson(
      HitFlash(remaining: 0.2, tintArgb: 0xFF00FF00).toJson(),
    );
    expect(decoded.remaining, 0.2);
    expect(decoded.tintArgb, 0xFF00FF00);
  });

  test('HitFlashSystem tints Sprite while remaining, then clears', () {
    final world = build();
    final id = world.spawn();
    world.componentsOf<Sprite>().set(id, Sprite('a', 'r'));
    world.componentsOf<HitFlash>().set(id, HitFlash(remaining: 0.1));

    world.step(0.05);
    expect(world.componentsOf<Sprite>().get(id)!.tintArgb, kDefaultHitFlashTint);
    expect(world.componentsOf<HitFlash>().get(id)!.remaining, greaterThan(0));

    world.step(0.1);
    expect(world.componentsOf<HitFlash>().get(id)!.remaining, 0);
    expect(world.componentsOf<Sprite>().get(id)!.tintArgb, isNull);
  });

  test('flashHit refreshes remaining on an entity with HitFlash', () {
    final world = build();
    final id = world.spawn();
    world.componentsOf<Sprite>().set(id, Sprite('a', 'r'));
    world.componentsOf<HitFlash>().set(id, HitFlash());

    flashHit(world, id, seconds: 0.2, tintArgb: 0xFFAABBCC);
    expect(world.componentsOf<HitFlash>().get(id)!.remaining, 0.2);
    expect(world.componentsOf<HitFlash>().get(id)!.tintArgb, 0xFFAABBCC);

    world.step(0.01);
    expect(world.componentsOf<Sprite>().get(id)!.tintArgb, 0xFFAABBCC);
  });

  test('flashHit is a no-op without a HitFlash component', () {
    final world = build();
    final id = world.spawn();
    flashHit(world, id);
    expect(world.componentsOf<HitFlash>().get(id), isNull);
  });
}
