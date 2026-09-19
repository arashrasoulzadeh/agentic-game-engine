import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('FleeBehavior', () {
    late World world;
    late BehaviorRegistry registry;

    setUp(() {
      world = World(width: 500, height: 500);
      registerCoreComponents(world);
      registry = BehaviorRegistry();
      world.addSystem(AISystem(registry));
    });

    test('flees horizontally from target', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100));

      final fleer = world.spawn();
      final target = 999;
      world.storeOf<Position>().set(fleer, Position(100, 100));
      world.storeOf<Position>().set(target, Position(150, 100));
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel, isNotNull);
      expect(vel!.x, -100); // target is to the right, so flee left
      expect(vel.y, 0); // doesn't touch y
    });

    test('flees right when target is to the left', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100));

      final fleer = world.spawn();
      final target = 999;
      world.storeOf<Position>().set(fleer, Position(100, 100));
      world.storeOf<Position>().set(target, Position(50, 100));
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel!.x, 100); // target is to the left, so flee right
    });

    test('stops when at or beyond minDistance', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100, minDistance: 50));

      final fleer = world.spawn();
      final target = 999;
      world.storeOf<Position>().set(fleer, Position(100, 100));
      world.storeOf<Position>().set(target, Position(50, 100)); // distance 50 == minDistance
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel!.x, 0); // at minDistance, stops
    });

    test('continues fleeing until stopBoundary (minDistance - stopDistance)', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100, minDistance: 50, stopDistance: 2));

      final fleer = world.spawn();
      final target = 999;
      world.storeOf<Position>().set(fleer, Position(100, 100));
      world.storeOf<Position>().set(target, Position(140, 100)); // distance 40, stopBoundary = 48
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel!.x, -100); // 40 < 48, still fleeing
    });

    test('stops when within stopDistance of minDistance (at stopBoundary)', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100, minDistance: 50, stopDistance: 10));

      final fleer = world.spawn();
      final target = 999;
      world.storeOf<Position>().set(fleer, Position(100, 100));
      world.storeOf<Position>().set(target, Position(145, 100)); // distance 45, stopBoundary = 40
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel!.x, 0); // 45 >= 40, at stopBoundary, stops
    });

    test('does not fight gravity - preserves existing y velocity', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100));

      final fleer = world.spawn();
      final target = 999;
      world.storeOf<Position>().set(fleer, Position(100, 100));
      world.storeOf<Position>().set(target, Position(150, 100));
      world.storeOf<Velocity>().set(fleer, Velocity(0, 200)); // falling
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel!.x, -100);
      expect(vel.y, 200); // y preserved
    });

    test('stops when line of sight blocked and requireLineOfSight=true', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100, requireLineOfSight: true));

      final fleer = world.spawn();
      final target = 999;
      world.storeOf<Position>().set(fleer, Position(100, 100));
      world.storeOf<Position>().set(target, Position(150, 100));
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      // Add a TileMap with a solid wall between fleer and target
      final map = world.spawn();
      world.storeOf<Position>().set(map, Position(0, 0));
      final tiles = List.filled(100, 0);
      // Wall at column 3 (x=96-128), row 3 (y=96-128) blocks line from (100,100) to (150,100)
      tiles[3 * 10 + 3] = 1;
      world.storeOf<TileMap>().set(map, TileMap(
        cols: 10, rows: 10, tileWidth: 32, tileHeight: 32,
        tiles: tiles,
        solidTileIds: {1},
      ));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel!.x, 0);
    });

    test('flees when line of sight clear and requireLineOfSight=true', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100, requireLineOfSight: true));

      final fleer = world.spawn();
      final target = 999;
      world.storeOf<Position>().set(fleer, Position(100, 100));
      world.storeOf<Position>().set(target, Position(150, 100));
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      // Add a TileMap far away so it doesn't block
      final map = world.spawn();
      world.storeOf<Position>().set(map, Position(0, 0));
      world.storeOf<TileMap>().set(map, TileMap(
        cols: 10, rows: 10, tileWidth: 32, tileHeight: 32,
        tiles: List.filled(100, 0),
        solidTileIds: {},
      ));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel!.x, -100);
    });

    test('returns NoOpAction when self or target has no Position', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100));

      final fleer = world.spawn();
      // No position on fleer
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel, isNull);
    });

    test('flees indefinitely when no minDistance set', () {
      registry.register('flee', FleeBehavior(target: 999, speed: 100));

      final fleer = world.spawn();
      final target = 999;
      world.storeOf<Position>().set(fleer, Position(100, 100));
      world.storeOf<Position>().set(target, Position(1000, 100)); // very far
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      world.step(0.016);

      final vel = world.storeOf<Velocity>().get(fleer);
      expect(vel!.x, -100); // still flees even when far
    });
  });
}