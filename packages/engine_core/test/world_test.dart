import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 200, height: 200);
  registerCoreComponents(world);
  world.addSystem(MovementSystem());
  world.addSystem(CollisionSystem());
  return world;
}

void main() {
  test('entities can be spawned and destroyed', () {
    final world = _buildWorld();
    final id = world.spawn();
    expect(world.entities.isAlive(id), isTrue);
    world.destroy(id);
    expect(world.entities.isAlive(id), isFalse);
  });

  test('movement system integrates position by velocity and bounces off walls', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(195, 100));
    world.storeOf<Velocity>().set(id, Velocity(50, 0));
    world.storeOf<Collider>().set(id, Collider(5));

    world.step(1.0); // would move to x=245, past the 200-wide world -> bounce

    final pos = world.storeOf<Position>().get(id)!;
    final vel = world.storeOf<Velocity>().get(id)!;
    expect(pos.x, lessThanOrEqualTo(195));
    expect(vel.x, lessThan(0));
  });

  test('collision system detects overlap and emits CollisionEvent', () {
    final world = _buildWorld();
    final a = world.spawn();
    final b = world.spawn();
    world.storeOf<Position>().set(a, Position(100, 100));
    world.storeOf<Velocity>().set(a, Velocity(10, 0));
    world.storeOf<Collider>().set(a, Collider(5));
    world.storeOf<Position>().set(b, Position(102, 100));
    world.storeOf<Velocity>().set(b, Velocity(-10, 0));
    world.storeOf<Collider>().set(b, Collider(5));

    var collided = false;
    world.events.on<CollisionEvent>((e) => collided = true);

    world.step(0.0); // dt=0 so movement doesn't move them apart first

    expect(collided, isTrue);
  });

  test('world state round-trips through toJson/applyPatch', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Position>().set(id, Position(10, 20));
    world.storeOf<Velocity>().set(id, Velocity(1, 2));
    world.storeOf<Collider>().set(id, Collider(3));

    final snapshot = world.toJson();
    expect(snapshot['entities'], hasLength(1));

    final world2 = _buildWorld();
    final id2 = world2.spawn();
    // patch targets id2, so remap the snapshot's entity id onto it
    final patched = {
      'entities': [
        {
          'id': id2,
          'components': (snapshot['entities'] as List).first['components'],
        }
      ]
    };
    world2.applyPatch(patched);

    final restored = world2.storeOf<Position>().get(id2)!;
    expect(restored.x, 10);
    expect(restored.y, 20);
  });

  test('systemOrder lists every registered system\'s name, and tick counts steps', () {
    final world = _buildWorld();
    world.addSystem(AISystem(BehaviorRegistry()));
    world.addSystem(ParticleSystem());

    expect(world.systemOrder, ['movement', 'collision', 'ai', 'particle']);
    expect(world.tick, 0);

    world.step(0.016);
    world.step(0.016);
    expect(world.tick, 2);
  });

  test('EventBus.clearHandlers removes every previously registered listener', () {
    final world = _buildWorld();
    var count = 0;
    world.events.on<CollisionEvent>((e) => count++);

    world.events.clearHandlers();
    world.events.emit(CollisionEvent(0, 1));
    world.events.flush();

    expect(count, 0);
  });

  test('spatial hash keeps collision system correct at higher entity counts', () {
    final world = _buildWorld();
    for (var i = 0; i < 500; i++) {
      final id = world.spawn();
      world.storeOf<Position>().set(id, Position((i % 20) * 10.0, (i ~/ 20) * 10.0));
      world.storeOf<Velocity>().set(id, Velocity(0, 0));
      world.storeOf<Collider>().set(id, Collider(4));
    }

    var collisionCount = 0;
    world.events.on<CollisionEvent>((e) => collisionCount++);
    world.step(0.016);

    expect(collisionCount, greaterThan(0));
  });

  group('applyPatch malformed input', () {
    test('missing "entities" key is a no-op, not an error', () {
      final world = _buildWorld();
      expect(() => world.applyPatch({}), returnsNormally);
    });

    test('throws WorldPatchException when "entities" is not a list', () {
      final world = _buildWorld();
      expect(
        () => world.applyPatch({'entities': 'not a list'}),
        throwsA(isA<WorldPatchException>()),
      );
    });

    test('throws WorldPatchException when an entity entry is not an object', () {
      final world = _buildWorld();
      expect(
        () => world.applyPatch({
          'entities': ['not an object'],
        }),
        throwsA(isA<WorldPatchException>()),
      );
    });

    test('throws WorldPatchException when an entity id is missing/wrong type', () {
      final world = _buildWorld();
      expect(
        () => world.applyPatch({
          'entities': [
            {'components': {}},
          ],
        }),
        throwsA(isA<WorldPatchException>()),
      );
    });

    test('a patch entry for a dead/unknown entity id is silently skipped', () {
      final world = _buildWorld();
      expect(
        () => world.applyPatch({
          'entities': [
            {'id': 999999, 'components': {}},
          ],
        }),
        returnsNormally,
      );
    });

    test('throws WorldPatchException when components is not an object', () {
      final world = _buildWorld();
      final id = world.spawn();
      expect(
        () => world.applyPatch({
          'entities': [
            {'id': id, 'components': 'not an object'},
          ],
        }),
        throwsA(isA<WorldPatchException>()),
      );
    });

    test('propagates ComponentApplyException from a malformed component payload', () {
      final world = _buildWorld();
      final id = world.spawn();
      expect(
        () => world.applyPatch({
          'entities': [
            {
              'id': id,
              'components': {'position': 'not an object'},
            },
          ],
        }),
        throwsA(isA<ComponentApplyException>()),
      );
    });
  });
}
