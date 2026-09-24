import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('ECS integration', () {
    test('full simulation tick: MovementSystem + CollisionSystem + ParticleSystem + TweenSystem', () {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);

      world.addSystem(MovementSystem());
      world.addSystem(CollisionSystem());
      world.addSystem(ParticleSystem());
      world.addSystem(TweenSystem());

      // Two entities moving toward each other
      final a = world.spawn();
      world.storeOf<Position>().set(a, Position(100, 100));
      world.storeOf<Velocity>().set(a, Velocity(100, 0));
      world.storeOf<Collider>().set(a, Collider(20));

      final b = world.spawn();
      world.storeOf<Position>().set(b, Position(300, 100));
      world.storeOf<Velocity>().set(b, Velocity(-100, 0));
      world.storeOf<Collider>().set(b, Collider(20));

      // Particle emitter
      final emitter = world.spawn();
      world.storeOf<Position>().set(emitter, Position(400, 100));
      world.storeOf<ParticleEmitter>().set(emitter, ParticleEmitter(rate: 5, speedMin: 10, speedMax: 20));

      // Tween
      final tweenEntity = world.spawn();
      world.storeOf<Tween>().set(tweenEntity, Tween(
        from: 0, to: 100, duration: 1.0, easing: EasingType.easeInOutQuad,
      ));

      // Run several ticks
      for (int i = 0; i < 10; i++) {
        world.step(0.1);
      }

      // Entities should have collided and bounced
      final velA = world.storeOf<Velocity>().get(a)!;
      final velB = world.storeOf<Velocity>().get(b)!;

      // They should have swapped velocities (roughly)
      expect(velA.x, lessThan(0));
      expect(velB.x, greaterThan(0));

      // Particles should exist - use WorldView
      final view = WorldView(world);
      final particles = view.entitiesWith<Particle>();
      expect(particles.length, greaterThan(0));

      // Tween should have progressed
      final tween = world.storeOf<Tween>().get(tweenEntity)!;
      expect(tween.value, greaterThan(0));
    });

    test('World.toJson produces valid JSON with all registered component types', () {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);

      // Create entity with core component types
      final e = world.spawn();
      world.storeOf<Position>().set(e, Position(123, 456));
      world.storeOf<Velocity>().set(e, Velocity(10, -20));
      world.storeOf<Collider>().set(e, Collider(15));
      world.storeOf<AIState>().set(e, AIState('test_behavior', memory: {'key': 'value'}));
      world.storeOf<ParticleEmitter>().set(e, ParticleEmitter(rate: 5, burstCount: 10));
      world.storeOf<Tween>().set(e, Tween(from: 0, to: 1, duration: 0.5));
      world.storeOf<Button>().set(e, Button('test'));
      world.storeOf<ButtonHitBox>().set(e, ButtonHitBox(50, 30));
      world.storeOf<RoomExit>().set(e, RoomExit('next_room', 'spawn_here'));
      world.storeOf<TriggerZone>().set(e, TriggerZone('my_trigger'));
      world.storeOf<Pushable>().set(e, Pushable());

      // TileMap
      final mapEntity = world.spawn();
      world.storeOf<Position>().set(mapEntity, Position(0, 0));
      world.storeOf<TileMap>().set(mapEntity, TileMap(
        cols: 10, rows: 10, tileWidth: 32, tileHeight: 32,
        tiles: List.generate(100, (i) => i % 2),
        solidTileIds: {1},
      ));

      // Serialize - this should not throw
      final json = world.toJson();

      // Verify structure
      expect(json['tick'], 0);
      expect(json['width'], 800);
      expect(json['height'], 600);
      expect(json['entities'], isA<List>());
      expect(json['entities'].length, 2);

      // Check first entity has all components
      final entityJson = json['entities'][0]['components'] as Map;
      expect(entityJson['position'], {'x': 123, 'y': 456});
      expect(entityJson['velocity'], {'x': 10, 'y': -20});
      expect(entityJson['collider']['radius'], 15);
      expect(entityJson['collider']['blocksLight'], false);
      expect(entityJson['collider']['pushable'], true);
      expect(entityJson['aiState']['behaviorId'], 'test_behavior');
      expect(entityJson['aiState']['memory']['key'], 'value');
      expect(entityJson['particleEmitter']['rate'], 5);
      expect(entityJson['tween']['from'], 0);
      expect(entityJson['button']['actionId'], 'test');
      expect(entityJson['buttonHitBox']['width'], 50);
      expect(entityJson['roomExit']['targetSceneId'], 'next_room');
      expect(entityJson['triggerZone']['triggerId'], 'my_trigger');
      expect(entityJson['pushable'], isA<Map>());

      // Check second entity is TileMap
      final tileMapJson = json['entities'][1]['components']['tileMap'] as Map;
      expect(tileMapJson['cols'], 10);
      expect(tileMapJson['solidTileIds'], [1]);
    });

    test('AISystem with multiple behaviors and WorldView queries', () {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);

      // Target entity (just Position, no AIState)
      final target = world.spawn();
      world.storeOf<Position>().set(target, Position(400, 300));

      final registry = BehaviorRegistry()
        ..register('chase', _ChaseBehavior())
        ..register('flee', FleeBehavior(target: target, speed: 50, minDistance: 100));

      world.addSystem(AISystem(registry));

      // Chaser
      final chaser = world.spawn();
      world.storeOf<Position>().set(chaser, Position(100, 100));
      world.storeOf<Velocity>().set(chaser, Velocity(0, 0));
      world.storeOf<AIState>().set(chaser, AIState('chase'));

      // Fleer
      final fleer = world.spawn();
      world.storeOf<Position>().set(fleer, Position(450, 300));
      world.storeOf<Velocity>().set(fleer, Velocity(0, 0));
      world.storeOf<AIState>().set(fleer, AIState('flee'));

      world.step(0.1);

      // Chaser moves toward target
      final chaserVel = world.storeOf<Velocity>().get(chaser)!;
      expect(chaserVel.x, greaterThan(0));
      expect(chaserVel.y, greaterThan(0));

      // Fleer moves away from target
      final fleerVel = world.storeOf<Velocity>().get(fleer)!;
      expect(fleerVel.x, greaterThan(0)); // target is at x=400, fleer at x=450 -> flees right

      // WorldView queries
      final view = WorldView(world);
      final nearTarget = view.entitiesWithinRadius(400, 300, 100);
      expect(nearTarget.length, 2); // target + fleer (chaser is far)

      final withAI = view.entitiesWith<AIState>();
      expect(withAI.length, 2); // chaser + fleer (target has no AIState)
    });
  });
}

class _ChaseBehavior implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) {
    final pos = view.component<Position>(self);
    final target = view.nearestWithPosition(pos!.x, pos.y, exclude: self);
    if (target == null) return const NoOpAction();
    final t = view.component<Position>(target)!;
    return SetVelocityAction(self, (t.x - pos.x).sign * 50, (t.y - pos.y).sign * 50);
  }
}