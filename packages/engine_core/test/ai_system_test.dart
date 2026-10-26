import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// Always sets velocity toward the nearest other entity with a Position —
/// a minimal "chase" behavior exercising the full Behavior -> Action ->
/// World mutation path.
class _ChaseNearestBehavior implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) {
    final selfPos = view.component<Position>(self);
    if (selfPos == null) return const NoOpAction();

    final target = view.nearestWithPosition(
      selfPos.x,
      selfPos.y,
      exclude: self,
    );
    if (target == null) return const NoOpAction();

    final targetPos = view.component<Position>(target)!;
    final dx = targetPos.x - selfPos.x;
    final dy = targetPos.y - selfPos.y;
    return SetVelocityAction(self, dx, dy);
  }
}

void main() {
  test('AISystem resolves each entity\'s behavior and applies its action', () {
    final world = World(width: 500, height: 500);
    registerCoreComponents(world);

    final registry = BehaviorRegistry();
    registry.register('chase', _ChaseNearestBehavior());
    world.addSystem(AISystem(registry));

    final chaser = world.spawn();
    final target = world.spawn();
    world.storeOf<Position>().set(chaser, Position(0, 0));
    world.storeOf<Position>().set(target, Position(10, 20));
    world.storeOf<AIState>().set(chaser, AIState('chase'));

    world.step(0.016);

    final vel = world.storeOf<Velocity>().get(chaser);
    expect(vel, isNotNull);
    expect(vel!.x, 10);
    expect(vel.y, 20);
  });

  test('BehaviorRegistry.resolve throws for an unregistered id', () {
    final registry = BehaviorRegistry();
    expect(() => registry.resolve('missing'), throwsArgumentError);
    expect(registry.has('missing'), isFalse);
  });

  test('AIState round-trips through toJson/fromJson', () {
    final state = AIState('patrol', memory: {'waypointIndex': 2});
    final restored = AIState.fromJson(state.toJson());
    expect(restored.behaviorId, 'patrol');
    expect(restored.memory['waypointIndex'], 2);
  });

  test('World.deltaTime tracks the dt of the current step', () {
    final world = World(width: 10, height: 10);
    expect(world.deltaTime, 0);
    world.step(0.05);
    expect(world.deltaTime, 0.05);
    world.step(1 / 30);
    expect(world.deltaTime, closeTo(1 / 30, 1e-12));
  });

  test('BehaviorTreeBehavior BTWait uses World.deltaTime, not 1/60', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    world.components.register<_Flag>(
      '_Flag',
      (v) => {'on': v.on},
      (j) => _Flag(j['on'] as bool? ?? false),
    );

    final registry = BehaviorRegistry();
    registry.register('mark', _MarkFlagBehavior());
    final tree = BTSequence(
      children: [
        BTWait(duration: 0.2, id: 'w'),
        BTLeaf(behaviorId: 'mark'),
      ],
    );
    registry.register(
      'waiter',
      BehaviorTreeBehavior(root: tree, registry: registry),
    );
    world.addSystem(AISystem(registry));

    final entity = world.spawn();
    world.storeOf<AIState>().set(
      entity,
      AIState('waiter', memory: {'_bt_blackboard': {}}),
    );
    world.storeOf<_Flag>().set(entity, _Flag(false));

    // Hardcoded 1/60 would leave Wait running after one 0.25s step.
    world.step(0.25);
    expect(world.storeOf<_Flag>().get(entity)!.on, isTrue);
  });

  test('StateMachineBehavior BTWait uses World.deltaTime, not 1/60', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    world.components.register<_Flag>(
      '_Flag',
      (v) => {'on': v.on},
      (j) => _Flag(j['on'] as bool? ?? false),
    );

    final registry = BehaviorRegistry();
    registry.register('mark', _MarkFlagBehavior());
    final machine = StateMachine(
      id: 'm',
      states: {
        'wait': FSMState(
          name: 'wait',
          behaviorTree: BTSequence(
            children: [
              BTWait(duration: 0.2, id: 'w'),
              BTLeaf(behaviorId: 'mark'),
            ],
          ),
        ),
      },
      initialState: 'wait',
    );
    registry.register(
      'fsm',
      StateMachineBehavior(stateMachine: machine, registry: registry),
    );
    world.addSystem(AISystem(registry));

    final entity = world.spawn();
    world.storeOf<AIState>().set(
      entity,
      AIState('fsm', memory: {'_fsm_blackboard': {}}),
    );
    world.storeOf<_Flag>().set(entity, _Flag(false));

    world.step(0.25);
    expect(world.storeOf<_Flag>().get(entity)!.on, isTrue);
  });

  test('BehaviorTreeSystem stashes real dt for BTWait', () {
    final world = World(width: 100, height: 100);
    registerCoreComponents(world);
    world.components.register<_Flag>(
      '_Flag',
      (v) => {'on': v.on},
      (j) => _Flag(j['on'] as bool? ?? false),
    );

    final registry = BehaviorRegistry();
    registry.register('mark', _MarkFlagBehavior());
    world.addSystem(BehaviorTreeSystem(registry));

    final entity = world.spawn();
    world.storeOf<_Flag>().set(entity, _Flag(false));
    world.storeOf<AIState>().set(
      entity,
      AIState(
        'unused',
        memory: {
          '_bt_root': {
            'type': 'sequence',
            'children': [
              {'type': 'wait', 'id': 'w', 'duration': 0.2},
              {'type': 'leaf', 'behaviorId': 'mark'},
            ],
          },
          '_bt_blackboard': <String, dynamic>{},
        },
      ),
    );

    world.step(0.25);
    expect(world.storeOf<_Flag>().get(entity)!.on, isTrue);
  });
}

class _Flag {
  bool on;
  _Flag(this.on);
}

class _MarkFlagBehavior implements Behavior {
  @override
  Action decide(WorldView view, EntityId self) => _MarkFlagAction(self);
}

class _MarkFlagAction implements Action {
  final EntityId entity;
  _MarkFlagAction(this.entity);

  @override
  void apply(World world) {
    world.storeOf<_Flag>().get(entity)?.on = true;
  }
}
