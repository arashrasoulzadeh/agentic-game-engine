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

    final target = view.nearestWithPosition(selfPos.x, selfPos.y, exclude: self);
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
}
