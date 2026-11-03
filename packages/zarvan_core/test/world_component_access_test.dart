import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

class _Unregistered {}

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

void main() {
  group('component access', () {
    test('set then get round-trips, and a second set replaces', () {
      final world = _world();
      final id = world.spawn();
      world.setComponent(id, Position(1, 2));
      expect(world.getComponent<Position>(id)!.x, 1);
      world.setComponent(id, Position(5, 6));
      expect(world.getComponent<Position>(id)!.x, 5);
      expect(world.componentsOf<Position>().length, 1);
    });

    test(
      'get is null and has is false when the entity lacks the component',
      () {
        final world = _world();
        final id = world.spawn();
        expect(world.getComponent<Position>(id), isNull);
        expect(world.hasComponent<Position>(id), isFalse);
        world.setComponent(id, Position(0, 0));
        expect(world.hasComponent<Position>(id), isTrue);
      },
    );

    test('remove detaches only that component and is a no-op when absent', () {
      final world = _world();
      final id = world.spawn();
      world.setComponent(id, Position(0, 0));
      world.setComponent(id, Velocity(1, 1));
      world.removeComponent<Position>(id);
      world.removeComponent<Position>(id);
      expect(world.hasComponent<Position>(id), isFalse);
      expect(world.hasComponent<Velocity>(id), isTrue);
    });

    test('an unregistered type fails with the registration hint', () {
      final world = _world();
      final id = world.spawn();
      expect(
        () => world.getComponent<_Unregistered>(id),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('is not registered'),
          ),
        ),
      );
    });
  });

  group('dead entities', () {
    test('setComponent on a destroyed entity throws and names the entity', () {
      final world = _world();
      final id = world.spawn();
      world.destroy(id);
      expect(
        () => world.setComponent(id, Position(0, 0)),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('entity $id'), contains('not alive')),
          ),
        ),
      );
      expect(
        world.componentsOf<Position>().length,
        0,
        reason: 'a rejected set must not leave a component behind',
      );
    });

    test('setComponent on a never-spawned id throws', () {
      final world = _world();
      expect(
        () => world.setComponent(42, Position(0, 0)),
        throwsA(isA<StateError>()),
      );
    });

    test('a destroyed id works again once a spawn has reused it', () {
      final world = _world();
      final old = world.spawn();
      world.destroy(old);
      final reused = world.spawn();
      expect(reused, old);
      world.setComponent(reused, Position(3, 4));
      expect(world.getComponent<Position>(old)!.x, 3);
    });

    test('get, has and remove on a dead entity are harmless', () {
      final world = _world();
      final id = world.spawn();
      world.setComponent(id, Position(0, 0));
      world.destroy(id);
      expect(world.getComponent<Position>(id), isNull);
      expect(world.hasComponent<Position>(id), isFalse);
      world.removeComponent<Position>(id);
    });
  });

  group('destroy cleans up everywhere', () {
    test('removes the entity from every store', () {
      final world = _world();
      final keep = world.spawn();
      final id = world.spawn();
      for (final e in [keep, id]) {
        world.setComponent(e, Position(0, 0));
        world.setComponent(e, Velocity(0, 0));
        world.setComponent(e, Collider(1));
      }
      world.destroy(id);
      expect(world.componentsOf<Position>().length, 1);
      expect(world.componentsOf<Velocity>().length, 1);
      expect(world.componentsOf<Collider>().length, 1);
      expect(world.getComponent<Position>(keep), isNotNull);
      expect(world.entities.isAlive(id), isFalse);
      expect(world.entities.isAlive(keep), isTrue);
    });

    test('forgets the entity in the archetype index and in serialization', () {
      final world = _world();
      final id = world.spawn();
      world.components.applyToEntity(id, {
        'position': {'x': 1.0, 'y': 2.0},
        'velocity': {'x': 0.0, 'y': 0.0},
      });
      expect(world.archetypes.getArchetype(id), isNotNull);
      world.destroy(id);
      expect(world.archetypes.getArchetype(id), isNull);
      expect(world.components.serializeEntity(id), isEmpty);
      expect(world.toJson()['entities'], isEmpty);
    });

    test('archetype index is only updated by registry-level writes: a '
        'component set through setComponent is not tracked (pinned so '
        'Phase 3 queries do not silently rely on archetypes)', () {
      final world = _world();
      final id = world.spawn();
      world.setComponent(id, Position(0, 0));
      expect(world.archetypes.getArchetype(id), isNull);
    });
  });
}
