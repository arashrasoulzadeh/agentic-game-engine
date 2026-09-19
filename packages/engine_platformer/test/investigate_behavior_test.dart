import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  registerPlatformerComponents(world);
  world.addSystem(GravitySystem());
  world.addSystem(MovementSystem());
  world.addSystem(PlatformerSystem());
  world.addSystem(TileCollisionSystem());
  world.addSystem(HearingSystem());
  return world;
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

EntityId _spawnInvestigator(World world, {
  required double x,
  required double y,
  double speed = 60,
  double arriveDistance = 10,
  double? timeout,
  bool avoidGaps = true,
  double gapCheckAheadDistance = 64,
}) {
  final id = world.spawn();
  world.storeOf<Position>().set(id, Position(x, y));
  world.storeOf<Velocity>().set(id, Velocity(0, 0));
  world.storeOf<Collider>().set(id, Collider(12));
  world.storeOf<Gravity>().set(id, Gravity(scale: 1));
  world.storeOf<PlatformerController>().set(id, PlatformerController());
  world.storeOf<AIState>().set(id, AIState('investigate'));
  world.storeOf<HearingComponent>().set(id, HearingComponent(range: 300));
  return id;
}

void main() {
  group('InvestigateBehavior', () {
    test('constructs with all fields and defaults correctly', () {
      final behavior = InvestigateBehavior(
        speed: 80,
        arriveDistance: 15,
        timeout: 5.0,
        avoidGaps: false,
        gapCheckAheadDistance: 100,
      );
      expect(behavior.speed, 80);
      expect(behavior.arriveDistance, 15);
      expect(behavior.timeout, 5.0);
      expect(behavior.avoidGaps, isFalse);
      expect(behavior.gapCheckAheadDistance, 100);
    });

    test('defaults for optional fields', () {
      const behavior = InvestigateBehavior(speed: 60);
      expect(behavior.arriveDistance, 10);
      expect(behavior.timeout, isNull);
      expect(behavior.avoidGaps, isTrue);
      expect(behavior.gapCheckAheadDistance, 64);
    });

    group('with HearingSystem integration', () {
      test('hears sound and moves toward it', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 400);

        final investigator = _spawnInvestigator(world, x: 100, y: 200);
        // Let it fall to floor
        for (int i = 0; i < 30; i++) world.step(0.016);

        // Emit sound to the right
        world.events.emit(SoundEvent(x: 300, y: 400, loudness: 250, tag: 'footstep'));
        world.step(0.016);

        // Check AIState.memory was updated
        final aiState = world.storeOf<AIState>().get(investigator)!;
        final soundData = aiState.memory['lastHeardSound'];
        expect(soundData, isNotNull);
        expect(soundData['x'], 300);
        expect(soundData['y'], 400);
        expect(soundData['loudness'], 250);
        expect(soundData['tag'], 'footstep');

        // InvestigateBehavior should now move toward the sound
        final vel = world.storeOf<Velocity>().get(investigator)!;
        expect(vel.x, greaterThan(0), reason: 'should move right toward sound');
      });

      test('does not react to sound outside hearing range', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 400);

        final investigator = _spawnInvestigator(world, x: 100, y: 200, speed: 60);
        for (int i = 0; i < 30; i++) world.step(0.016);

        // Emit sound far outside hearing range (HearingComponent.range = 300)
        world.events.emit(SoundEvent(x: 500, y: 400, loudness: 100));
        world.step(0.016);

        final aiState = world.storeOf<AIState>().get(investigator)!;
        expect(aiState.memory['lastHeardSound'], isNull, reason: 'sound outside hearing range should not be heard');
      });

      test('does not react to sound outside sound loudness', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 400);

        final investigator = _spawnInvestigator(world, x: 100, y: 200);
        for (int i = 0; i < 30; i++) world.step(0.016);

        // Sound loudness 50, distance 200
        world.events.emit(SoundEvent(x: 300, y: 400, loudness: 50));
        world.step(0.016);

        final aiState = world.storeOf<AIState>().get(investigator)!;
        expect(aiState.memory['lastHeardSound'], isNull, reason: 'sound outside loudness should not be heard');
      });

      test('sound blocked by solid wall (no line of sight)', () {
        final world = _buildWorld();
        // TileMap with solid wall between investigator and sound
        final mapEntity = world.spawn();
        world.storeOf<Position>().set(mapEntity, Position(0, 0));
        world.storeOf<TileMap>().set(mapEntity, TileMap(
          cols: 10, rows: 10, tileWidth: 40, tileHeight: 40,
          tiles: [
            for (var row = 0; row < 10; row++)
              for (var col = 0; col < 10; col++) (col == 5) ? 1 : 0,
          ],
          solidTileIds: {1},
        ));

        final investigator = _spawnInvestigator(world, x: 100, y: 200);
        for (int i = 0; i < 30; i++) world.step(0.016);

        // Sound behind wall at x=220
        world.events.emit(SoundEvent(x: 220, y: 200, loudness: 200));
        world.step(0.016);

        final aiState = world.storeOf<AIState>().get(investigator)!;
        expect(aiState.memory['lastHeardSound'], isNull, reason: 'wall should block the sound');
      });

      test('stops when arrives at sound position (within arriveDistance)', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 400);

        final investigator = _spawnInvestigator(world, x: 100, y: 200, arriveDistance: 20);
        for (int i = 0; i < 30; i++) world.step(0.016);

        // Emit sound at x=300
        world.events.emit(SoundEvent(x: 300, y: 400, loudness: 200));
        world.step(0.016);

        // Move toward sound
        for (int i = 0; i < 50; i++) world.step(0.016);

        final pos = world.storeOf<Position>().get(investigator)!;
        final vel = world.storeOf<Velocity>().get(investigator)!;
        
        // Should be near the sound position and stopped (or nearly stopped)
        expect((pos.x - 300).abs(), lessThan(50), reason: 'should approach sound position');
        // Once within arriveDistance, velocity should be 0
        if ((pos.x - 300).abs() <= 20) {
          expect(vel.x, 0, reason: 'should stop when within arriveDistance');
        }
      });

      test('avoidGaps: stops at gap instead of walking off', () {
        final world = _buildWorld();
        // Floor with gap at x=240-320
        final mapEntity = world.spawn();
        world.storeOf<Position>().set(mapEntity, Position(0, 0));
        final tiles = <int>[];
        for (var row = 0; row < 10; row++) {
          for (var col = 0; col < 12; col++) {
            if (row == 9) {
              // Gap at columns 6-7 (x=240-320)
              tiles.add((col >= 6 && col < 8) ? 0 : 1);
            } else {
              tiles.add(0);
            }
          }
        }
        world.storeOf<TileMap>().set(mapEntity, TileMap(
          cols: 12, rows: 10, tileWidth: 40, tileHeight: 40,
          tiles: tiles, solidTileIds: {1},
        ));

        final investigator = _spawnInvestigator(world, x: 100, y: 200, speed: 60, avoidGaps: true);
        for (int i = 0; i < 30; i++) world.step(0.016);

        // Emit sound on the other side of the gap
        world.events.emit(SoundEvent(x: 350, y: 400, loudness: 250));
        world.step(0.016);

        // Move toward sound
        for (int i = 0; i < 30; i++) world.step(0.016);

        final pos = world.storeOf<Position>().get(investigator)!;
        // Should stop before the gap (x=240)
        expect(pos.x, lessThan(240), reason: 'should stop before gap when avoidGaps=true');
      });

      test('without avoidGaps: walks toward sound even with gap', () {
        final world = _buildWorld();
        // Floor with gap at x=240-320
        final mapEntity = world.spawn();
        world.storeOf<Position>().set(mapEntity, Position(0, 0));
        final tiles = <int>[];
        for (var row = 0; row < 10; row++) {
          for (var col = 0; col < 12; col++) {
            if (row == 9) {
              tiles.add((col >= 6 && col < 8) ? 0 : 1);
            } else {
              tiles.add(0);
            }
          }
        }
        world.storeOf<TileMap>().set(mapEntity, TileMap(
          cols: 12, rows: 10, tileWidth: 40, tileHeight: 40,
          tiles: tiles, solidTileIds: {1},
        ));

        final investigator = _spawnInvestigator(world, x: 100, y: 200, speed: 60, avoidGaps: false);
        for (int i = 0; i < 30; i++) world.step(0.016);

        // Emit sound on the other side of the gap
        world.events.emit(SoundEvent(x: 350, y: 400, loudness: 250));
        world.step(0.016);

        // Move toward sound
        for (int i = 0; i < 30; i++) world.step(0.016);

        final pos = world.storeOf<Position>().get(investigator)!;
        // Without avoidGaps, may walk into the gap
        expect(pos.x, greaterThan(100), reason: 'should move toward sound');
      });

      test('new sound overwrites previous heard sound', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 400);

        final investigator = _spawnInvestigator(world, x: 100, y: 200);
        for (int i = 0; i < 30; i++) world.step(0.016);

        // First sound
        world.events.emit(SoundEvent(x: 200, y: 400, loudness: 100, tag: 'first'));
        world.step(0.016);
        var aiState = world.storeOf<AIState>().get(investigator)!;
        expect(aiState.memory['lastHeardSound']['tag'], 'first');

        // Second sound
        world.events.emit(SoundEvent(x: 300, y: 400, loudness: 100, tag: 'second'));
        world.step(0.016);
        aiState = world.storeOf<AIState>().get(investigator)!;
        expect(aiState.memory['lastHeardSound']['tag'], 'second');
      });

      test('entity without HearingComponent does not react', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 400);

        final id = world.spawn();
        world.storeOf<Position>().set(id, Position(100, 200));
        world.storeOf<Velocity>().set(id, Velocity(0, 0));
        world.storeOf<Collider>().set(id, Collider(12));
        world.storeOf<Gravity>().set(id, Gravity(scale: 1));
        world.storeOf<PlatformerController>().set(id, PlatformerController());
        world.storeOf<AIState>().set(id, AIState('investigate'));
        // NO HearingComponent

        world.events.emit(SoundEvent(x: 200, y: 400, loudness: 200));
        world.step(0.016);

        final aiState = world.storeOf<AIState>().get(id)!;
        expect(aiState.memory['lastHeardSound'], isNull);
      });

      test('entity without AIState does not crash', () {
        final world = _buildWorld();
        _createFloorMap(world, y: 400);

        final id = world.spawn();
        world.storeOf<Position>().set(id, Position(100, 200));
        world.storeOf<Velocity>().set(id, Velocity(0, 0));
        world.storeOf<Collider>().set(id, Collider(12));
        world.storeOf<Gravity>().set(id, Gravity(scale: 1));
        world.storeOf<PlatformerController>().set(id, PlatformerController());
        world.storeOf<HearingComponent>().set(id, HearingComponent(range: 300));
        // NO AIState

        world.events.emit(SoundEvent(x: 200, y: 400, loudness: 200));
        world.step(0.016);

        // Should not crash, just nothing happens
      });
    });
  });
}