// The Light2D samples in docs/concepts/lighting.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a flickering torch swings around its base values; a steady light does not', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(LightFlickerSystem());

    final torch = world.spawn();
    world.storeOf<Position>().set(torch, Position(10, 10));
    final light = Light2D(radius: 120, intensity: 0.8, flickerSpeed: 3, flickerAmount: 0.3);
    world.storeOf<Light2D>().set(torch, light);

    final lamp = world.spawn();
    final steady = Light2D(radius: 80, intensity: 0.6);
    world.storeOf<Light2D>().set(lamp, steady);

    final seen = <double>{};
    for (var i = 0; i < 60; i++) {
      world.step(1 / 30);
      seen.add(light.intensity);
    }
    expect(seen.length, greaterThan(10), reason: 'it varies');
    expect(light.baseIntensity, 0.8, reason: 'the base is what it oscillates around');
    expect(light.intensity, lessThanOrEqualTo(1.0));
    expect((steady.intensity, steady.radius), (0.6, 80));
  });

  test('flickerAffectsRadius: false keeps the shadow geometry stable', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    world.addSystem(LightFlickerSystem());
    final e = world.spawn();
    final light = Light2D(radius: 100, flickerSpeed: 4, flickerAffectsRadius: false);
    world.storeOf<Light2D>().set(e, light);
    for (var i = 0; i < 20; i++) {
      world.step(1 / 30);
      expect(light.radius, 100);
    }
  });

  test('a light is plain data and survives a JSON round trip', () {
    final light = Light2D(radius: 150, intensity: 0.9, colorArgb: 0xAAFF6600, coneAngle: 1.0, castsShadows: true);
    final back = Light2D.fromJson(light.toJson());
    expect(back.radius, 150);
    expect(back.colorArgb, 0xAAFF6600);
    expect(back.coneAngle, 1.0);
    expect(back.castsShadows, isTrue);
    expect(back.useGpuShadows, isFalse, reason: 'off by default');
  });
}
