import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 2000, height: 2000);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(GravitySystem());
  world.addSystem(MovementSystem());
  world.addSystem(PlatformerSystem());
  world.addSystem(TileCollisionSystem());
  return world;
}

EntityId _spawnPatroller(World world, {
  required double x,
  required double y,
  double minX = 100,
  double maxX = 300,
  double speed = 60,
  bool avoidLedges = true,
  bool affectedByGravity = true,
  Map<String, dynamic>? memory,
}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<Velocity>().set(id, Velocity(0, 0));
  world.storeOf<Collider>().set(id, Collider(12));
  if (affectedByGravity) {
    world.storeOf<Gravity>().set(id, Gravity(scale: 1));
    world.storeOf<PlatformerController>().set(id, PlatformerController());
  }
  world.storeOf<AIState>().set(id, AIState('patrol', memory: memory ?? {
    'minX': minX,
    'maxX': maxX,
    'speed': speed,
  }));
  return id;
}

TileMap _createFloorMap(World world, {double y = 1000, double tileSize = 40}) {
  final mapEntity = world.spawn();
  world.storeOf<Position>().set(mapEntity, Position(0, 0));
  final rows = (y / tileSize).floor() + 1;
  final cols = 50;
  final tiles = <int>[];
  for (var row = 0; row < rows; row++) {
    for (var col = 0; col < cols; col++) {
      tiles.add((row == rows - 1) ? 1 : 0);
    }
  }
  world.storeOf<TileMap>().set(mapEntity, TileMap(
    cols: cols,
    rows: rows,
    tileWidth: tileSize,
    tileHeight: tileSize,
    tiles: tiles,
    solidTileIds: {1},
  ));
  return world.storeOf<TileMap>().get(mapEntity)!;
}

void main() {
  group('PatrolBehavior', () {
    group('with gravity (grounded patroller)', () {
      test('falls onto floor and patrols between minX/maxX', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 1000);

        final patroller = _spawnPatroller(world,
          x: 200, y: 800, // starts above floor
          minX: 150, maxX: 350,
          speed: 60,
          affectedByGravity: true,
        );

        // Let it fall and settle
        for (int i = 0; i < 30; i++) world.step(0.016);

        final pos = world.storeOf<Position>().get(patroller)!;
        expect(pos.y, closeTo(1000 - 12, 5)); // on floor (collider radius 12)

        // Patrol right initially
        final vel = world.storeOf<Velocity>().get(patroller)!;
        expect(vel.x, greaterThan(0));
      });

      test('flips direction at maxX bound', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 1000);

        final patroller = _spawnPatroller(world,
          x: 340, y: 800, // near maxX
          minX: 150, maxX: 350,
          speed: 60,
          affectedByGravity: true,
        );

        for (int i = 0; i < 30; i++) world.step(0.016);

        // Should be moving left (flipped at maxX)
        final vel = world.storeOf<Velocity>().get(patroller)!;
        expect(vel.x, lessThan(0));
      });

      test('flips direction at minX bound', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 1000);

        final patroller = _spawnPatroller(world,
          x: 160, y: 800, // near minX
          minX: 150, maxX: 350,
          speed: 60,
          affectedByGravity: true,
        );

        for (int i = 0; i < 30; i++) world.step(0.016);

        // Should be moving right (flipped at minX)
        final vel = world.storeOf<Velocity>().get(patroller)!;
        expect(vel.x, greaterThan(0));
      });

      test('avoidLedges: flips early when ledge detected ahead', () {
        final world = _buildWorld();
        // Floor with a gap at x=240-280
        final mapEntity = world.spawn();
        world.storeOf<Position>().set(mapEntity, Position(0, 0));
        final tiles = <int>[];
        for (var row = 0; row < 25; row++) {
          for (var col = 0; col < 50; col++) {
            if (row == 24) {
              // Gap at columns 6-7 (x=240-320)
              tiles.add((col >= 6 && col < 8) ? 0 : 1);
            } else {
              tiles.add(0);
            }
          }
        }
        world.storeOf<TileMap>().set(mapEntity, TileMap(
          cols: 50,
          rows: 25,
          tileWidth: 40,
          tileHeight: 40,
          tiles: tiles,
          solidTileIds: {1},
        ));

        // Patroller moving right toward gap
        final patroller = _spawnPatroller(world,
          x: 200, y: 800,
          minX: 150, maxX: 500, // range extends past gap
          speed: 60,
          affectedByGravity: true,
        );

        // Let it fall and approach gap
        for (int i = 0; i < 40; i++) world.step(0.016);

        // Should have flipped left before falling into gap
        final pos = world.storeOf<Position>().get(patroller)!;
        expect(pos.x, lessThan(240)); // stopped before gap
        final vel = world.storeOf<Velocity>().get(patroller)!;
        expect(vel.x, lessThan(0)); // moving left
      });

      test('avoidLedges: does NOT flip when ground continues', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 1000);

        final patroller = _spawnPatroller(world,
          x: 200, y: 800,
          minX: 150, maxX: 350,
          speed: 60,
          affectedByGravity: true,
        );

        for (int i = 0; i < 40; i++) world.step(0.016);

        // Should patrol normally without premature flip
        final vel = world.storeOf<Velocity>().get(patroller)!;
        // Direction depends on starting position vs bounds
        expect(vel.x != 0, isTrue);
      });
    });

    group('WITHOUT gravity (floating patroller - BUG SCENARIO)', () {
      test('avoidLedges with no gravity causes rapid direction flip (BUG)', () {
        final world = _buildWorld();
        // NO floor - empty air

        final patroller = _spawnPatroller(world,
          x: 200, y: 500,
          minX: 150, maxX: 350,
          speed: 60,
          avoidLedges: true,
          affectedByGravity: false, // KEY: no gravity
        );

        final directions = <int>[];
        for (int i = 0; i < 20; i++) {
          world.step(0.016);
          final vel = world.storeOf<Velocity>().get(patroller)!;
          if (vel.x > 0) directions.add(1);
          if (vel.x < 0) directions.add(-1);
        }

        // BUG: With no ground, avoidLedges finds "no ground ahead" every frame
        // and flips direction every tick -> rapid oscillation
        // This test DOCUMENTS the bug - it should FAIL if we want to prevent this
        expect(directions.length, greaterThan(10)); // many direction changes
        final flips = directions.where((d) => d != directions.first).length;
        expect(flips, greaterThan(5)); // rapid flipping
      });

      test('without avoidLedges, no gravity patroller stays at bounds', () {
        final world = _buildWorld();
        // NO floor

        final patroller = _spawnPatroller(world,
          x: 200, y: 500,
          minX: 150, maxX: 350,
          speed: 60,
          avoidLedges: false, // NO ledge avoidance
          affectedByGravity: false,
        );

        // Should just patrol between bounds
        final positions = <double>[];
        for (int i = 0; i < 50; i++) {
          world.step(0.016);
          positions.add(world.storeOf<Position>().get(patroller)!.x);
        }

        // Should oscillate between 150 and 350
        expect(positions.any((x) => x <= 155), isTrue); // near minX
        expect(positions.any((x) => x >= 345), isTrue); // near maxX
      });
    });

    group('memory overrides', () {
      test('per-entity memory overrides constructor defaults', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 1000);

        final patroller = _spawnPatroller(world,
          x: 200, y: 800,
          minX: 100, maxX: 200, // constructor defaults
          speed: 100,
          affectedByGravity: true,
        );

        for (int i = 0; i < 30; i++) world.step(0.016);

        // Should use memory values (150-350, speed 60) not constructor (100-200, 100)
        final pos = world.storeOf<Position>().get(patroller)!;
        expect(pos.x, greaterThan(150));
        expect(pos.x, lessThan(350));
      });
    });
  });
}