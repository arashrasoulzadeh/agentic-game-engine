import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  group('WaterZone', () {
    test('defaults and round-trips through toJson/fromJson', () {
      final zone = WaterZone(200, 100);
      expect(zone.maxFallSpeed, 80);
      expect(zone.swimUpSpeed, 140);

      final custom = WaterZone(50, 60, maxFallSpeed: 40, swimUpSpeed: 200);
      final restored = WaterZone.fromJson(custom.toJson());
      expect(restored.width, 50);
      expect(restored.height, 60);
      expect(restored.maxFallSpeed, 40);
      expect(restored.swimUpSpeed, 200);
    });
  });

  group('PlatformerController.inWater', () {
    test('defaults to false and round-trips through toJson/fromJson', () {
      expect(PlatformerController().inWater, isFalse);
      final restored = PlatformerController.fromJson(PlatformerController(inWater: true).toJson());
      expect(restored.inWater, isTrue);
    });
  });

  group('WaterPhysicsSystem', () {
    test('an entity outside any WaterZone is untouched, inWater stays false', () {
      final world = _buildWorld();
      world.addSystem(WaterPhysicsSystem());

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 500));
      world.storeOf<Collider>().set(id, Collider(10));
      final controller = PlatformerController();
      world.storeOf<PlatformerController>().set(id, controller);

      final zoneEntity = world.spawn();
      world.storeOf<Position>().set(zoneEntity, Position(1000, 1000));
      world.storeOf<WaterZone>().set(zoneEntity, WaterZone(50, 50));

      world.step(0.016);

      expect(controller.inWater, isFalse);
      expect(world.storeOf<Velocity>().get(id)!.y, 500);
    });

    test('submerged entity falling faster than maxFallSpeed is clamped to it', () {
      final world = _buildWorld();
      world.addSystem(WaterPhysicsSystem());

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 500));
      world.storeOf<Collider>().set(id, Collider(10));
      final controller = PlatformerController();
      world.storeOf<PlatformerController>().set(id, controller);

      final zoneEntity = world.spawn();
      world.storeOf<Position>().set(zoneEntity, Position(0, 0));
      world.storeOf<WaterZone>().set(zoneEntity, WaterZone(100, 100, maxFallSpeed: 60));

      world.step(0.016);

      expect(controller.inWater, isTrue);
      expect(world.storeOf<Velocity>().get(id)!.y, 60);
    });

    test('submerged entity falling slower than maxFallSpeed is left alone', () {
      final world = _buildWorld();
      world.addSystem(WaterPhysicsSystem());

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 20));
      world.storeOf<Collider>().set(id, Collider(10));
      final controller = PlatformerController();
      world.storeOf<PlatformerController>().set(id, controller);

      final zoneEntity = world.spawn();
      world.storeOf<Position>().set(zoneEntity, Position(0, 0));
      world.storeOf<WaterZone>().set(zoneEntity, WaterZone(100, 100, maxFallSpeed: 60));

      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, 20,
          reason: 'already slower than the buoyancy cap -- nothing to clamp');
    });

    test('jumpRequested while submerged applies an upward stroke and is consumed', () {
      final world = _buildWorld();
      world.addSystem(WaterPhysicsSystem());

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 500));
      world.storeOf<Collider>().set(id, Collider(10));
      final controller = PlatformerController(jumpRequested: true);
      world.storeOf<PlatformerController>().set(id, controller);

      final zoneEntity = world.spawn();
      world.storeOf<Position>().set(zoneEntity, Position(0, 0));
      world.storeOf<WaterZone>().set(zoneEntity, WaterZone(100, 100, swimUpSpeed: 150));

      world.step(0.016);

      expect(world.storeOf<Velocity>().get(id)!.y, -150);
      expect(controller.jumpRequested, isFalse,
          reason: 'consumed by the stroke so JumpSystem does not also try to jump with it');
    });

    test('repeated jumpRequested presses give repeated strokes, not one arc', () {
      final world = _buildWorld();
      world.addSystem(WaterPhysicsSystem());

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<Collider>().set(id, Collider(10));
      final controller = PlatformerController();
      world.storeOf<PlatformerController>().set(id, controller);

      final zoneEntity = world.spawn();
      world.storeOf<Position>().set(zoneEntity, Position(0, 0));
      world.storeOf<WaterZone>().set(zoneEntity, WaterZone(100, 100, swimUpSpeed: 150));

      controller.jumpRequested = true;
      world.step(0.016);
      expect(world.storeOf<Velocity>().get(id)!.y, -150);

      // Simulate a second press after the first stroke -- another
      // stroke fires, not a no-op the way a held single-jump would be.
      controller.jumpRequested = true;
      world.step(0.016);
      expect(world.storeOf<Velocity>().get(id)!.y, -150);
    });

    test('an entity with no Collider/Velocity/Position is skipped gracefully, not a crash', () {
      final world = _buildWorld();
      world.addSystem(WaterPhysicsSystem());

      final id = world.spawn();
      world.storeOf<PlatformerController>().set(id, PlatformerController());

      final zoneEntity = world.spawn();
      world.storeOf<Position>().set(zoneEntity, Position(0, 0));
      world.storeOf<WaterZone>().set(zoneEntity, WaterZone(100, 100));

      expect(() => world.step(0.016), returnsNormally);
    });

    test('does nothing at all when no WaterZone exists in the world', () {
      final world = _buildWorld();
      world.addSystem(WaterPhysicsSystem());

      final id = world.spawn();
      world.storeOf<Position>().set(id, Position(0, 0));
      world.storeOf<Velocity>().set(id, Velocity(0, 500));
      world.storeOf<Collider>().set(id, Collider(10));
      final controller = PlatformerController();
      world.storeOf<PlatformerController>().set(id, controller);

      world.step(0.016);

      expect(controller.inWater, isFalse);
      expect(world.storeOf<Velocity>().get(id)!.y, 500);
    });
  });

  group('installPlatformerSystems + WaterZone end-to-end', () {
    test('a player entity swims (buoyancy-capped fall) once overlapping a WaterZone',
        () {
      final world = _buildWorld();
      final player = world.spawn();
      world.storeOf<Position>().set(player, Position(0, 0));
      world.storeOf<Velocity>().set(player, Velocity(0, 0));
      world.storeOf<Collider>().set(player, Collider(10));
      world.storeOf<InputState>().set(player, InputState());
      world.storeOf<Gravity>().set(player, Gravity());
      final controller = PlatformerController();
      world.storeOf<PlatformerController>().set(player, controller);

      final zoneEntity = world.spawn();
      world.storeOf<Position>().set(zoneEntity, Position(0, 0));
      world.storeOf<WaterZone>().set(zoneEntity, WaterZone(200, 200, maxFallSpeed: 50));

      installPlatformerSystems(world, player: player);

      for (var i = 0; i < 30; i++) {
        world.step(0.016);
      }

      expect(controller.inWater, isTrue);
      expect(world.storeOf<Velocity>().get(player)!.y, lessThanOrEqualTo(50),
          reason: 'gravity would otherwise have accelerated well past this over 30 ticks');
    });
  });
}
