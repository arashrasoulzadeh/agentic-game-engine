import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  World w() {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    return world;
  }

  test(
    'findNear returns entities in range, nearest first, honoring exclude',
    () {
      final world = w();
      final far = world.spawnAt(50, 0);
      final near = world.spawnAt(3, 0);
      final mid = world.spawnAt(0, 10);
      world.spawnAt(500, 500);
      expect(world.findNear(0, 0, 60), [near, mid, far]);
      expect(world.findNear(0, 0, 5), [near]);
      expect(world.findNear(0, 0, 60, exclude: near), [mid, far]);
    },
  );

  test('raycast hits the nearest collider and honors exclude', () {
    final world = w();
    final caster = world.spawnWith([Position(0, 0), Collider(2)]);
    final target = world.spawnWith([Position(20, 0), Collider(2)]);
    final hit = world.raycast(0, 0, 40, 0, exclude: caster);
    expect(hit!.entity, target);
    expect(world.raycast(0, 10, 40, 10), isNull);
  });

  test('TileMap world-coordinate helpers convert and read tiles', () {
    final map = TileMap(
      cols: 2,
      rows: 2,
      tileWidth: 16,
      tileHeight: 16,
      tiles: [0, 1, 0, 0],
      solidTileIds: {1},
    );
    expect(map.colAtX(17), 1);
    expect(map.rowAtY(-0.1), -1);
    expect(map.tileAtWorld(20, 5), 1);
    expect(map.isSolidAtWorld(20, 5), isTrue);
    expect(map.isSolidAtWorld(5, 5), isFalse);
    expect(map.isSolidAtWorld(-5, 5), isFalse);
  });
}
