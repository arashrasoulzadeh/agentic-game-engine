import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  return world;
}

void main() {
  test('addTag creates the component and hasTag sees it', () {
    final world = _world();
    final id = world.spawn();
    expect(world.hasTag(id, 'enemy'), isFalse);
    world.addTag(id, 'enemy');
    world.addTag(id, 'boss');
    world.addTag(id, 'enemy');
    expect(world.hasTag(id, 'enemy'), isTrue);
    expect(world.getComponent<EntityTags>(id)!.values, {'enemy', 'boss'});
  });

  test('removeTag drops the component when the last tag goes', () {
    final world = _world();
    final id = world.spawn();
    world.addTag(id, 'a');
    world.addTag(id, 'b');
    world.removeTag(id, 'a');
    expect(world.hasComponent<EntityTags>(id), isTrue);
    world.removeTag(id, 'b');
    expect(world.hasComponent<EntityTags>(id), isFalse);
    world.removeTag(id, 'b');
  });

  test('withTag finds exactly the tagged entities', () {
    final world = _world();
    final a = world.spawn();
    final b = world.spawn();
    final c = world.spawn();
    world.addTag(a, 'enemy');
    world.addTag(b, 'pickup');
    world.addTag(c, 'enemy');
    world.addTag(c, 'pickup');
    expect(world.withTag('enemy').toSet(), {a, c});
    expect(world.withTag('pickup').toSet(), {b, c});
    expect(world.withTag('nothing'), isEmpty);
  });

  test('addTag on a dead entity throws like setComponent', () {
    final world = _world();
    final id = world.spawn();
    world.destroy(id);
    expect(() => world.addTag(id, 'x'), throwsStateError);
  });

  test('tags serialize sorted, round-trip through patches and spawnWith', () {
    final world = _world();
    final id = world.spawnWith([
      EntityTags(['zeta', 'alpha']),
    ]);
    expect(world.components.serializeEntity(id)['tags'], {
      'tags': ['alpha', 'zeta'],
    });
    final other = _world();
    other.entities.ensureAlive(id);
    other.applyPatch(world.toJson());
    expect(other.getComponent<EntityTags>(id)!.values, {'alpha', 'zeta'});
  });

  test('a tags component with no list loads as empty', () {
    expect(EntityTags.fromJson({}).values, isEmpty);
  });

  test('destroy removes the entity from withTag', () {
    final world = _world();
    final id = world.spawn();
    world.addTag(id, 'enemy');
    world.destroy(id);
    expect(world.withTag('enemy'), isEmpty);
  });
}
