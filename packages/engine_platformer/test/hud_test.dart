import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 1000, height: 1000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  group('HudBar', () {
    test('fraction clamps to [0, 1] and treats maxValue <= 0 as empty', () {
      expect(HudBar(value: 5, maxValue: 10).fraction, 0.5);
      expect(HudBar(value: 20, maxValue: 10).fraction, 1);
      expect(HudBar(value: -5, maxValue: 10).fraction, 0);
      expect(HudBar(value: 5, maxValue: 0).fraction, 0);
    });

    test('round-trips through toJson/fromJson', () {
      final bar = HudBar(
        value: 3,
        maxValue: 10,
        width: 80,
        height: 10,
        fillColorArgb: 0xFF00FF00,
        backgroundColorArgb: 0xFF111111,
        zIndex: 5,
      );
      final restored = HudBar.fromJson(bar.toJson());
      expect(restored.value, 3);
      expect(restored.maxValue, 10);
      expect(restored.width, 80);
      expect(restored.height, 10);
      expect(restored.fillColorArgb, 0xFF00FF00);
      expect(restored.backgroundColorArgb, 0xFF111111);
      expect(restored.zIndex, 5);
    });
  });

  group('spawnHealthHudBar / HealthHudSystem', () {
    test('syncs HudBar.value/maxValue from the linked Health each tick', () {
      final world = _buildWorld();
      world.addSystem(HealthHudSystem());

      final player = world.spawn();
      world.storeOf<Health>().set(player, Health(current: 40, max: 100));

      final bar = spawnHealthHudBar(world, source: player, x: 10, y: 10);
      expect(world.storeOf<HudBar>().get(bar)!.value, 0, reason: 'not synced until the first step');

      world.step(0.016);

      final hudBar = world.storeOf<HudBar>().get(bar)!;
      expect(hudBar.value, 40);
      expect(hudBar.maxValue, 100);
    });

    test('stays in sync as Health changes', () {
      final world = _buildWorld();
      world.addSystem(HealthHudSystem());

      final player = world.spawn();
      final health = Health(current: 100, max: 100);
      world.storeOf<Health>().set(player, health);
      final bar = spawnHealthHudBar(world, source: player, x: 10, y: 10);

      world.step(0.016);
      expect(world.storeOf<HudBar>().get(bar)!.value, 100);

      health.current = 25;
      world.step(0.016);
      expect(world.storeOf<HudBar>().get(bar)!.value, 25);
    });

    test('is a no-op (does not throw) when the linked source has no Health', () {
      final world = _buildWorld();
      world.addSystem(HealthHudSystem());

      final source = world.spawn(); // no Health
      final bar = spawnHealthHudBar(world, source: source, x: 10, y: 10);

      expect(() => world.step(0.016), returnsNormally);
      expect(world.storeOf<HudBar>().get(bar)!.value, 0);
    });
  });
}
