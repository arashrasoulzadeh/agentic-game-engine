import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Hurt {}

class _Mark implements Action {
  const _Mark(this.self);
  final EntityId self;
  @override
  void apply(World world) => world.setComponent(self, _Hurt());
}

World _world() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  world.components.register<_Hurt>('hurt', (_) => {}, (_) => _Hurt());
  return world;
}

void main() {
  group('setBehavior', () {
    test('points the entity at the behavior and clears old memory', () {
      final world = _world();
      final e = world.spawn();
      world.setComponent(e, AIState('idle', memory: {'seen': 1}));
      world.setBehavior(e, 'chase');
      final ai = world.getComponent<AIState>(e)!;
      expect(ai.behaviorId, 'chase');
      expect(ai.memory, isEmpty);
    });

    test('keepMemory carries the old memory over', () {
      final world = _world();
      final e = world.spawn();
      world.setComponent(e, AIState('idle', memory: {'seen': 1}));
      world.setBehavior(e, 'chase', keepMemory: true);
      expect(world.getComponent<AIState>(e)!.memory['seen'], 1);
    });

    test('an unknown id fails now when a registry is given', () {
      final world = _world();
      final e = world.spawn();
      expect(
        () => world.setBehavior(e, 'nope', behaviors: BehaviorRegistry()),
        throwsArgumentError,
      );
      expect(world.hasComponent<AIState>(e), isFalse);
    });
  });

  group('runTree and conditions', () {
    test('a tree drives the entity under AISystem, gated by a condition', () {
      final world = _world();
      final behaviors = BehaviorRegistry()
        ..registerInRange('playerNear', target: 'player', range: 50)
        ..registerFn('mark', (view, self) => _Mark(self));
      world.addSystem(AISystem(behaviors));
      final player = world.spawnWith([Position(0, 0)]);
      world.setName(player, 'player');
      final guard = world.spawnWith([Position(200, 0)]);
      world.runTree(
        guard,
        BT.sequence([BT.leaf('playerNear'), BT.leaf('mark')]),
        behaviors: behaviors,
      );

      world.step(0.016);
      expect(world.hasComponent<_Hurt>(guard), isFalse, reason: 'too far');

      world.getComponent<Position>(guard)!.x = 30;
      world.step(0.016);
      expect(world.hasComponent<_Hurt>(guard), isTrue, reason: 'in range');
    });

    test('inRange is false when the target does not exist', () {
      final world = _world();
      final behaviors = BehaviorRegistry()
        ..registerInRange('near', target: 'ghost', range: 1e9);
      final e = world.spawnWith([Position(0, 0)]);
      final action = behaviors.resolve('near').decide(WorldView(world), e);
      expect(action, isA<FailureAction>());
    });

    test('registerHas tests for a component', () {
      final world = _world();
      final behaviors = BehaviorRegistry()..registerHas<_Hurt>('hurt');
      final e = world.spawn();
      final view = WorldView(world);
      expect(behaviors.resolve('hurt').decide(view, e), isA<FailureAction>());
      world.setComponent(e, _Hurt());
      expect(behaviors.resolve('hurt').decide(view, e), isA<NoOpAction>());
    });

    test('re-running a tree replaces that entity tree', () {
      final world = _world();
      final behaviors = BehaviorRegistry()
        ..registerFn('mark', (view, self) => _Mark(self));
      final e = world.spawn();
      world.runTree(e, BT.leaf('mark'), behaviors: behaviors);
      world.runTree(e, BT.leaf('mark'), behaviors: behaviors);
      expect(world.getComponent<AIState>(e)!.behaviorId, 'tree@$e');
    });
  });
}
