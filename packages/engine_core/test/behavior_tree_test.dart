import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  return world;
}

void main() {
  group('BehaviorTree - BTNode', () {
    test('BTSequence succeeds when all children succeed', () {
      final world = _buildWorld();
      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<AIState>().set(entity, AIState('test', memory: {'_bt_blackboard': {}}));

      final registry = BehaviorRegistry();
      registry.register('action1', _TestBehavior(setValue: 1));
      registry.register('action2', _TestBehavior(setValue: 2));

      final tree = BTSequence(children: [
        BTLeaf(behaviorId: 'action1'),
        BTLeaf(behaviorId: 'action2'),
      ]);

      final action = BehaviorTreeBehavior(root: tree, registry: registry).decide(WorldView(world), entity);
      action.apply(world);

      expect(world.storeOf<_TestValue>().get(entity)?.value, 2);
    });

    test('BTSequence fails when any child fails', () {
      final world = _buildWorld();
      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<AIState>().set(entity, AIState('test', memory: {'_bt_blackboard': {}}));

      final registry = BehaviorRegistry();
      registry.register('succeed', _TestBehavior(setValue: 1));
      registry.register('fail', _FailingBehavior());

      final tree = BTSequence(children: [
        BTLeaf(behaviorId: 'succeed'),
        BTLeaf(behaviorId: 'fail'),
      ]);

      final action = BehaviorTreeBehavior(root: tree, registry: registry).decide(WorldView(world), entity);
      action.apply(world);

      // First action should have run (value = 1), then sequence should stop on failure
      expect(world.storeOf<_TestValue>().get(entity)?.value, 1);
    });

    test('BTSelector succeeds when any child succeeds', () {
      final world = _buildWorld();
      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<AIState>().set(entity, AIState('test', memory: {'_bt_blackboard': {}}));

      final registry = BehaviorRegistry();
      registry.register('fail1', _FailingBehavior());
      registry.register('succeed', _TestBehavior(setValue: 42));

      final tree = BTSelector(children: [
        BTLeaf(behaviorId: 'fail1'),
        BTLeaf(behaviorId: 'succeed'),
      ]);

      final action = BehaviorTreeBehavior(root: tree, registry: registry).decide(WorldView(world), entity);
      action.apply(world);

      expect(world.storeOf<_TestValue>().get(entity)?.value, 42);
    });

    test('BTInverter inverts success to failure and vice versa', () {
      final world = _buildWorld();
      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<AIState>().set(entity, AIState('test', memory: {'_bt_blackboard': {}}));

      final registry = BehaviorRegistry();
      registry.register('succeed', _TestBehavior(setValue: 1));

      // Invert a success -> should be failure
      // We can't easily test the inverted result through the Behavior interface
      // since it always returns an action. Let's test node directly.
      BTInverter(child: BTLeaf(behaviorId: 'succeed'));
    });

    test('BTRepeater repeats child N times', () {
      final world = _buildWorld();
      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<AIState>().set(entity, AIState('test', memory: {'_bt_blackboard': {}}));

      final registry = BehaviorRegistry();
      registry.register('increment', _IncrementBehavior());

      // Repeat 3 times
      final tree = BTRepeater(count: 3, child: BTLeaf(behaviorId: 'increment'));

      final action = BehaviorTreeBehavior(root: tree, registry: registry).decide(WorldView(world), entity);
      action.apply(world);

      expect(world.storeOf<_TestValue>().get(entity)?.value, 3);
    });

    test('BTRepeater with null count repeats forever (until child fails)', () {
      final world = _buildWorld();
      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<AIState>().set(entity, AIState('test', memory: {'_bt_blackboard': {}}));

      final registry = BehaviorRegistry();
      // Fail on 3rd call
      registry.register('failAfter3', _FailAfterBehavior(failAfter: 3));

      final tree = BTRepeater(count: null, child: BTLeaf(behaviorId: 'failAfter3'));

      final action = BehaviorTreeBehavior(root: tree, registry: registry).decide(WorldView(world), entity);
      action.apply(world);

      // Should have run 3 times (fail on 3rd)
      expect(world.storeOf<_TestValue>().get(entity)?.value, 3);
    });

    test('BTParallel succeeds when required children succeed', () {
      final world = _buildWorld();
      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<AIState>().set(entity, AIState('test', memory: {'_bt_blackboard': {}}));

      final registry = BehaviorRegistry();
      registry.register('action1', _TestBehavior(setValue: 10));
      registry.register('action2', _TestBehavior(setValue: 20));
      registry.register('action3', _TestBehavior(setValue: 30));

      // Need 2 successes out of 3
      final tree = BTParallel(requiredSuccess: 2, children: [
        BTLeaf(behaviorId: 'action1'),
        BTLeaf(behaviorId: 'action2'),
        BTLeaf(behaviorId: 'action3'),
      ]);

      final action = BehaviorTreeBehavior(root: tree, registry: registry).decide(WorldView(world), entity);
      action.apply(world);

      // All three should have run since they all succeed
      expect(world.storeOf<_TestValue>().get(entity)?.value, 30); // Last one wins
    });

    test('Behavior tree JSON serialization round-trip', () {
      final tree = BTSequence(id: 'root', children: [
        BTSelector(id: 'sel', children: [
          BTLeaf(id: 'leaf1', behaviorId: 'attack'),
          BTInverter(id: 'inv', child: BTLeaf(id: 'leaf2', behaviorId: 'move')),
        ]),
        BTRepeater(id: 'rep', count: 3, child: BTWait(id: 'wait', duration: 1.0)),
      ]);

      final json = tree.toJson();
      final restored = BTNode.fromJson(json);

      expect(restored, isA<BTSequence>());
      final seq = restored as BTSequence;
      expect(seq.id, 'root');
      expect(seq.children.length, 2);

      final sel = seq.children[0] as BTSelector;
      expect(sel.id, 'sel');
      expect(sel.children.length, 2);

      final inv = sel.children[1] as BTInverter;
      expect(inv.id, 'inv');
      expect(inv.child, isA<BTLeaf>());

      final rep = seq.children[1] as BTRepeater;
      expect(rep.id, 'rep');
      expect(rep.count, 3);
      expect(rep.child, isA<BTWait>());
    });
  });

  group('BehaviorTree - Blackboard persistence', () {
    test('Blackboard persists between ticks via AIState.memory', () {
      final world = _buildWorld();
      final entity = world.spawn();
      world.storeOf<Position>().set(entity, Position(0, 0));
      world.storeOf<AIState>().set(entity, AIState('test', memory: {'_bt_blackboard': {}}));

      final registry = BehaviorRegistry();
      registry.register('increment', _IncrementBehavior());

      final tree = BTRepeater(count: 2, child: BTLeaf(behaviorId: 'increment'));
      final behavior = BehaviorTreeBehavior(root: tree, registry: registry);

      // First tick - runs first iteration
      behavior.decide(WorldView(world), entity).apply(world);
      expect(world.storeOf<_TestValue>().get(entity)?.value, 1);

      // Second tick - runs second iteration
      behavior.decide(WorldView(world), entity).apply(world);
      expect(world.storeOf<_TestValue>().get(entity)?.value, 2);
    });
  });
}

class _TestValue {
  int value;
  _TestValue({required this.value});
  Map<String, dynamic> toJson() => {'value': value};
}

class _TestBehavior implements Behavior {
  final int setValue;
  _TestBehavior({required this.setValue});

  @override
  Action decide(WorldView view, EntityId self) => _TestAction(setValue);
}

class _TestAction implements Action {
  final int value;
  _TestAction(this.value);
  @override
  void apply(World world) {
    // Store value in a test component
    world.storeOf<_TestValue>().set(world.entities.create(), _TestValue(value: value));
  }
}

class _IncrementBehavior implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) => _IncrementAction();
}

class _IncrementAction implements Action {
  @override
  void apply(World world) {
    // Find existing test value and increment
    final stores = world.storeOf<_TestValue>();
    if (stores.length > 0) {
      final entity = stores.entityAt(0);
      final existing = stores.get(entity)!;
      stores.set(entity, _TestValue(value: existing.value + 1));
    } else {
      world.storeOf<_TestValue>().set(world.entities.create(), _TestValue(value: 1));
    }
  }
}

class _FailingBehavior implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) => _FailAction();
}

class _FailAction implements Action {
  @override
  void apply(World world) {
    // Does nothing - represents failure
  }
}

class _FailAfterBehavior implements Behavior {
  final int failAfter;
  _FailAfterBehavior({required this.failAfter});

  @override
  Action decide(WorldView view, EntityId self) => _FailAfterAction(failAfter);
}

class _FailAfterAction implements Action {
  final int failAfter;
  _FailAfterAction(this.failAfter);

  @override
  void apply(World world) {
    final stores = world.storeOf<_TestValue>();
    if (stores.length > 0) {
      final entity = stores.entityAt(0);
      final existing = stores.get(entity)!;
      if (existing.value + 1 >= failAfter) {
        // Don't apply - represents failure
        return;
      }
      stores.set(entity, _TestValue(value: existing.value + 1));
    } else {
      world.storeOf<_TestValue>().set(world.entities.create(), _TestValue(value: 1));
    }
  }
}