import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_testing.dart';
import 'package:test/test.dart';

class _Dead {}

void main() {
  test('spawnActor makes a findable, solid, movable entity', () {
    final t = GameTester();
    final id = t.spawnActor(x: 5, y: 6, radius: 3);
    expect(t.world.find('player'), id);
    expect(t.component<Position>(id).x, 5);
    expect(t.component<Collider>(id).radius, 3);
    expect(t.has<Velocity>(id), isTrue);
  });

  test('expectHas / expectMissing fail with a message naming the entity', () {
    final t = GameTester()
      ..world.components.register<_Dead>('dead', (_) => {}, (_) => _Dead());
    final id = t.spawnActor();
    t.expectMissing<_Dead>(id);
    expect(() => t.expectHas<_Dead>(id), throwsStateError);
    t.world.setComponent(id, _Dead());
    t.expectHas<_Dead>(id);
    expect(
      () => t.expectMissing<_Dead>(id),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('$id')),
      ),
    );
  });

  test('expectAlive / expectDestroyed track destroy', () {
    final t = GameTester();
    final id = t.spawnActor();
    t.expectAlive(id);
    expect(() => t.expectDestroyed(id), throwsStateError);
    t.world.destroy(id);
    t.expectDestroyed(id);
    expect(() => t.expectAlive(id), throwsStateError);
  });
}
