import '../behavior.dart';
import '../components/ai_state.dart';
import '../system.dart';
import '../world.dart';
import '../world_view.dart';

/// Drives every `AIState`-tagged entity by resolving its behavior and
/// applying the `Action` it returns. Behaviors see a fresh `WorldView`
/// each tick (built once per `update` call, not per entity — cheap,
/// and guarantees every behavior this tick sees the same snapshot).
class AISystem implements System {
  final BehaviorRegistry registry;

  AISystem(this.registry);

  @override
  String get name => 'ai';

  @override
  void update(World world, double dt) {
    final states = world.storeOf<AIState>();
    if (states.length == 0) return;

    final view = WorldView(world);
    for (var i = 0; i < states.length; i++) {
      final entity = states.entityAt(i);
      final state = states.denseAt(i);
      final behavior = registry.resolve(state.behaviorId);
      final action = behavior.decide(view, entity);
      action.apply(world);
    }
  }
}
