import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('HearingSystem', () {
    late World world;

    setUp(() {
      world = World(width: 500, height: 500);
      registerCoreComponents(world);
    });

    test('SoundEvent toJson/fromJson round-trips correctly', () {
      const sound = SoundEvent(x: 100, y: 200, loudness: 150, tag: 'gunshot', data: {'weapon': 'pistol'});
      final restored = SoundEvent.fromJson(sound.toJson());

      expect(restored.x, 100);
      expect(restored.y, 200);
      expect(restored.loudness, 150);
      expect(restored.tag, 'gunshot');
      expect(restored.data!['weapon'], 'pistol');
    });

    test('HearingComponent toJson/fromJson round-trips correctly', () {
      final hearing = HearingComponent(range: 200);
      final restored = HearingComponent.fromJson(hearing.toJson());
      expect(restored.range, 200);
    });

    test('HearingSystem registers subscription and processes sound event', () {
      world.addSystem(HearingSystem());

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(100, 100));
      world.storeOf<HearingComponent>().set(entity, HearingComponent(range: 200));
      world.storeOf<AIState>().set(entity, AIState('idle'));

      // Emit a sound within range
      world.events.emit(SoundEvent(x: 150, y: 100, loudness: 100, tag: 'footstep'));

      world.step(0.016);

      final aiState = world.storeOf<AIState>().get(entity)!;
      final soundData = aiState.memory['lastHeardSound'];
      expect(soundData, isNotNull);
      expect(soundData['x'], 150);
      expect(soundData['y'], 100);
      expect(soundData['loudness'], 100);
      expect(soundData['tag'], 'footstep');
    });

    test('Entity does not hear sound outside hearing range', () {
      world.addSystem(HearingSystem());

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(100, 100));
      world.storeOf<HearingComponent>().set(entity, HearingComponent(range: 50));
      world.storeOf<AIState>().set(entity, AIState('idle'));

      // Sound at distance 100, hearing range 50
      world.events.emit(SoundEvent(x: 200, y: 100, loudness: 100));

      world.step(0.016);

      final aiState = world.storeOf<AIState>().get(entity)!;
      expect(aiState.memory['lastHeardSound'], isNull);
    });

    test('Entity does not hear sound outside sound loudness', () {
      world.addSystem(HearingSystem());

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(100, 100));
      world.storeOf<HearingComponent>().set(entity, HearingComponent(range: 200));
      world.storeOf<AIState>().set(entity, AIState('idle'));

      // Sound loudness 50, distance 100
      world.events.emit(SoundEvent(x: 200, y: 100, loudness: 50));

      world.step(0.016);

      final aiState = world.storeOf<AIState>().get(entity)!;
      expect(aiState.memory['lastHeardSound'], isNull);
    });

    test('Sound is blocked by solid wall (no line of sight)', () {
      world.addSystem(HearingSystem());

      // TileMap with solid wall between entity and sound
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(mapEntity, TileMap(
        cols: 10, rows: 5, tileWidth: 40, tileHeight: 40,
        tiles: [
          for (var row = 0; row < 5; row++)
            for (var col = 0; col < 10; col++) (col == 3) ? 1 : 0,
        ],
        solidTileIds: {1},
      ));

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(100, 100));
      world.storeOf<HearingComponent>().set(entity, HearingComponent(range: 200));
      world.storeOf<AIState>().set(entity, AIState('idle'));

      // Sound behind wall at x=130
      world.events.emit(SoundEvent(x: 130, y: 100, loudness: 100));

      world.step(0.016);

      final aiState = world.storeOf<AIState>().get(entity)!;
      expect(aiState.memory['lastHeardSound'], isNull,
          reason: 'Wall should block the sound');
    });

    test('Sound is NOT blocked by one-way platform (default)', () {
      world.addSystem(HearingSystem());

      // TileMap with one-way platform (not solid)
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(mapEntity, TileMap(
        cols: 10, rows: 5, tileWidth: 40, tileHeight: 40,
        tiles: [
          for (var row = 0; row < 5; row++)
            for (var col = 0; col < 10; col++) (col == 3) ? 1 : 0,
        ],
        oneWayTileIds: {1}, // Not solid
      ));

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(100, 100));
      world.storeOf<HearingComponent>().set(entity, HearingComponent(range: 200));
      world.storeOf<AIState>().set(entity, AIState('idle'));

      // Sound behind one-way platform at x=130
      world.events.emit(SoundEvent(x: 130, y: 100, loudness: 100));

      world.step(0.016);

      final aiState = world.storeOf<AIState>().get(entity)!;
      expect(aiState.memory['lastHeardSound'], isNotNull,
          reason: 'One-way platform should not block sound by default');
      expect(aiState.memory['lastHeardSound']['x'], 130);
    });

    test('Multiple entities - only those in range hear the sound', () {
      world.addSystem(HearingSystem());

      final e1 = world.spawn();
      world.storeOf<Position>().set(e1, Position(100, 100));
      world.storeOf<HearingComponent>().set(e1, HearingComponent(range: 50));
      world.storeOf<AIState>().set(e1, AIState('idle'));

      final e2 = world.spawn();
      world.storeOf<Position>().set(e2, Position(200, 100));
      world.storeOf<HearingComponent>().set(e2, HearingComponent(range: 200));
      world.storeOf<AIState>().set(e2, AIState('idle'));

      // Sound at x=150, distance 50 from e1, 50 from e2
      world.events.emit(SoundEvent(x: 150, y: 100, loudness: 100));

      world.step(0.016);

      // e1: distance 50, range 50 -> hears (distance == range)
      final ai1 = world.storeOf<AIState>().get(e1)!;
      expect(ai1.memory['lastHeardSound'], isNotNull);

      // e2: distance 50, range 200 -> hears
      final ai2 = world.storeOf<AIState>().get(e2)!;
      expect(ai2.memory['lastHeardSound'], isNotNull);
    });

    test('New sound overwrites previous heard sound in memory', () {
      world.addSystem(HearingSystem());

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(100, 100));
      world.storeOf<HearingComponent>().set(entity, HearingComponent(range: 200));
      world.storeOf<AIState>().set(entity, AIState('idle'));

      // First sound
      world.events.emit(SoundEvent(x: 120, y: 100, loudness: 100, tag: 'first'));
      world.step(0.016);

      var aiState = world.storeOf<AIState>().get(entity)!;
      expect(aiState.memory['lastHeardSound']['tag'], 'first');

      // Second sound
      world.events.emit(SoundEvent(x: 130, y: 100, loudness: 100, tag: 'second'));
      world.step(0.016);

      aiState = world.storeOf<AIState>().get(entity)!;
      expect(aiState.memory['lastHeardSound']['tag'], 'second');
    });

    test('Entities without HearingComponent do not hear', () {
      world.addSystem(HearingSystem());

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(100, 100));
      world.storeOf<AIState>().set(entity, AIState('idle'));
      // No HearingComponent

      world.events.emit(SoundEvent(x: 150, y: 100, loudness: 100));
      world.step(0.016);

      final aiState = world.storeOf<AIState>().get(entity)!;
      expect(aiState.memory['lastHeardSound'], isNull);
    });

    test('Entities without AIState do not crash', () {
      world.addSystem(HearingSystem());

      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(100, 100));
      world.storeOf<HearingComponent>().set(entity, HearingComponent(range: 200));
      // No AIState

      world.events.emit(SoundEvent(x: 150, y: 100, loudness: 100));
      world.step(0.016);

      // Should not crash, just nothing happens
    });
  });
}