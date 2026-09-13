import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Fake {
  final int n;
  _Fake(this.n);
}

void main() {
  test('storeOf throws for a type that was never registered', () {
    final world = World(width: 10, height: 10);
    expect(() => world.storeOf<_Fake>(), throwsStateError);
  });

  test('registered component types serialize/deserialize by name', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);

    final id = world.spawn();
    world.storeOf<AIState>().set(id, AIState('patrol'));

    final serialized = world.components.serializeEntity(id);
    expect(serialized['aiState'], {'behaviorId': 'patrol', 'memory': <String, dynamic>{}});

    world.components.applyToEntity(id, {
      'aiState': {'behaviorId': 'chase', 'memory': <String, dynamic>{}},
    });
    expect(world.storeOf<AIState>().get(id)!.behaviorId, 'chase');
  });

  test('TileMap/Particle/ParticleEmitter serialize through World.toJson', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);

    final mapEntity = world.spawn();
    world.storeOf<TileMap>().set(
          mapEntity,
          TileMap(cols: 1, rows: 1, tileWidth: 10, tileHeight: 10, tiles: [1]),
        );

    final particleEntity = world.spawn();
    world.storeOf<Particle>().set(particleEntity, Particle(lifetime: 1));

    final emitterEntity = world.spawn();
    world.storeOf<ParticleEmitter>().set(emitterEntity, ParticleEmitter());

    final snapshot = world.toJson();
    final byId = {
      for (final e in snapshot['entities'] as List) (e as Map)['id']: e['components']
    };

    expect(byId[mapEntity]['tileMap']['cols'], 1);
    expect(byId[particleEntity]['particle']['lifetime'], 1);
    expect(byId[emitterEntity]['particleEmitter']['rate'], 0);
  });

  test('applyToEntity throws ComponentApplyException when a component value is not an object', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final id = world.spawn();

    expect(
      () => world.components.applyToEntity(id, {'aiState': 'not an object'}),
      throwsA(isA<ComponentApplyException>()
          .having((e) => e.componentName, 'componentName', 'aiState')
          .having((e) => e.entity, 'entity', id)),
    );
  });

  test('applyToEntity throws ComponentApplyException when fromJson itself rejects the data', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final id = world.spawn();

    // TileMap's constructor validates tiles.length == cols * rows and
    // throws on mismatch -- applyToEntity should wrap that, not let it
    // escape as a bare, contextless error.
    expect(
      () => world.components.applyToEntity(id, {
        'tileMap': {
          'cols': 2,
          'rows': 2,
          'tileWidth': 10,
          'tileHeight': 10,
          'tiles': [1], // wrong length
        },
      }),
      throwsA(isA<ComponentApplyException>()
          .having((e) => e.componentName, 'componentName', 'tileMap')),
    );
  });

  test('applyToEntity skips unknown component names without throwing', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    final id = world.spawn();

    expect(
      () => world.components.applyToEntity(id, {'notARealComponent': {}}),
      returnsNormally,
    );
  });
}
