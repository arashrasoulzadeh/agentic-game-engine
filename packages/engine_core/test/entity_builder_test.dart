import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _NotRegistered {}

class _FastVelocity extends Velocity {
  _FastVelocity() : super(99, 0);
}

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('spawnWith attaches every component to one new entity', () {
    final world = _world();
    final id = world.spawnWith([Position(10, 20), Velocity(5, 0)]);
    expect(world.getComponent<Position>(id)!.y, 20);
    expect(world.getComponent<Velocity>(id)!.x, 5);
    expect(world.entities.count, 1);
  });

  test('spawnWith round-trips through World.toJson/applyPatch', () {
    final world = _world();
    final id = world.spawnWith([Position(1, 2), Collider(3)]);
    final json = world.toJson();
    final other = _world();
    other.entities.ensureAlive(id);
    other.applyPatch(json);
    expect(other.getComponent<Position>(id)!.x, 1);
    expect(other.getComponent<Collider>(id)!.radius, 3);
  });

  test('an unregistered type throws and leaves no entity behind', () {
    final world = _world();
    expect(
      () => world.spawnWith([Position(0, 0), _NotRegistered()]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          contains('_NotRegistered is not registered'),
        ),
      ),
    );
    expect(world.entities.count, 0);
    expect(world.componentsOf<Position>().length, 0);
  });

  test('a type listed twice throws before spawning', () {
    final world = _world();
    expect(
      () => world.spawnWith([Position(0, 0), Position(1, 1)]),
      throwsA(isA<ArgumentError>()),
    );
    expect(world.entities.count, 0);
  });

  test('a subclass of a registered type is rejected (exact type match)', () {
    final world = _world();
    expect(
      () => world.spawnWith([_FastVelocity()]),
      throwsA(isA<ArgumentError>()),
    );
    expect(world.entities.count, 0);
  });

  test('the builder chains and build returns a live reference', () {
    final world = _world();
    final ref = world.entity().at(10, 20).add(Velocity(5, 0)).build();
    expect(ref.isAlive, isTrue);
    expect(ref.get<Position>()!.x, 10);
    expect(ref.get<Velocity>()!.x, 5);
  });

  test('nothing exists until build, and a builder is not consumed by it', () {
    final world = _world();
    final b = world.entity().at(1, 1);
    expect(world.entities.count, 0);
    final first = b.build();
    final second = b.build();
    expect(first.id, isNot(second.id));
    expect(world.entities.count, 2);
  });

  test('a builder with a bad component throws at build, not before', () {
    final world = _world();
    final b = world.entity().add(_NotRegistered());
    expect(b.build, throwsA(isA<ArgumentError>()));
    expect(world.entities.count, 0);
  });
}
