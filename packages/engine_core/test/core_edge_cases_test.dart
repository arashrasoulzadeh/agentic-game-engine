import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  test('UI and pushable components survive registry serialization', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    final id = world.spawn();
    final data = <String, dynamic>{
      'button': {'actionId': 'play'},
      'buttonHitBox': {'width': 220.0, 'height': 64.0},
      'triggerZone': {'triggerId': 'checkpoint', 'data': {'room': 2}},
      'pushable': {'pushSpeed': 45.0},
    };
    world.components.applyToEntity(id, data);
    expect(world.components.serializeEntity(id), data);
  });

  test('component errors identify the entity, field and underlying cause', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final id = world.spawn();
    try {
      world.components.applyToEntity(id, {'position': false});
      fail('Invalid component should throw');
    } on ComponentApplyException catch (error) {
      expect(error.toString(), contains('component "position" on entity $id'));
      expect(error.toString(), contains('expected an object, got bool'));
    }
    expect(WorldPatchException('invalid entity').toString(),
        'WorldPatchException: invalid entity');
  });

  test('boolean random sequence is reproducible after reset', () {
    final random = DeterministicRandom(47);
    final original = List.generate(32, (_) => random.nextBool());
    random.reset();
    expect(List.generate(32, (_) => random.nextBool()), original);
    expect(original, containsAll([true, false]));
  });

  test('skipping a callback cinematic completes once without replaying it', () {
    final world = World(width: 10, height: 10);
    var calls = 0;
    final cinematic = CinematicSystem([CallbackStep((_) => calls++)]);
    expect(cinematic.name, 'cinematic');
    cinematic.skip(world);
    cinematic.skip(world);
    cinematic.update(world, 1);
    expect(calls, 1);
    expect(cinematic.isPlaying, isFalse);
    expect(TileAnimationSystem().name, 'tileAnimation');
    expect(PushableSystem().name, 'pushable');
  });

  test('out-of-range authored clock hours fall back to night values', () {
    final midnight = DayNightCycle(hour: 24);
    for (final hour in [-1.0, 25.0]) {
      final cycle = DayNightCycle(hour: hour);
      expect(cycle.timeOfDayBrightness, midnight.timeOfDayBrightness);
      expect(cycle.ambientColorArgb, midnight.ambientColorArgb);
    }
  });

  test('an empty ASCII level is rejected with an actionable error', () {
    expect(
      () => TileMap.fromJson({
        'rows': <String>[],
        'legend': {'#': 1},
        'tileWidth': 16,
        'tileHeight': 16,
      }),
      throwsA(isA<ArgumentError>().having(
          (error) => error.message, 'message', contains('must not be empty'))),
    );
  });

  group('TMX structure validation', () {
    const start = '<map width="1" height="1" tilewidth="16" tileheight="16">';
    const tileset = '<tileset firstgid="1"/>';
    for (final (body, message) in [
      ('', 'No <tileset>'),
      (tileset, 'No <layer>'),
      ('$tileset<layer/>', '<layer> has no <data>'),
    ]) {
      test(message, () {
        expect(
          () => tileMapFromTmx('$start$body</map>'),
          throwsA(isA<UnsupportedError>().having(
              (error) => error.message, 'message', contains(message))),
        );
      });
    }
    test('left-rising slopes preserve the tileset global ID offset', () {
      final map = tileMapFromTmx('''$start
<tileset firstgid="7"><tile id="2"><properties>
<property name="slopeUpLeft" type="bool" value="true"/>
</properties></tile></tileset>
<layer><data encoding="csv">9</data></layer></map>''');
      expect(map.slopeUpLeftTileIds, {9});
      expect(map.tileAt(0, 0), 9);
    });
  });
}
