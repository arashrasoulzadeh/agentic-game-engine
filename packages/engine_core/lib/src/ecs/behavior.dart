import 'action.dart';
import 'entity.dart';
import 'world_view.dart';

/// The runtime-agent/NPC hook: implement [decide] to control an entity.
/// Only ever receives a read-only [WorldView] — it cannot mutate the
/// World directly, only propose an [Action] for `AISystem` to apply.
/// This is what lets an LLM-backed or rule-based agent drive a game
/// entity without any risk of it corrupting simulation state.
abstract class Behavior {
  Action decide(WorldView view, EntityId self);
}

/// A [Behavior] from a plain function, for trivial cases that don't earn a
/// class: `FunctionBehavior((view, self) => NoOpAction())`. Same sandbox as any
/// behavior: it only sees a [WorldView] and proposes an [Action].
class FunctionBehavior implements Behavior {
  final Action Function(WorldView view, EntityId self) _decide;

  /// Wraps [decide].
  FunctionBehavior(Action Function(WorldView view, EntityId self) decide)
    : _decide = decide;

  @override
  Action decide(WorldView view, EntityId self) => _decide(view, self);
}

/// Behaviors carry logic (closures/state machines), so — like
/// `AtlasRegistry` for sprites — they're registered under an id rather
/// than embedded in JSON. `AIState.behaviorId` references entries here.
class BehaviorRegistry {
  final Map<String, Behavior> _behaviors = {};

  void register(String id, Behavior behavior) => _behaviors[id] = behavior;

  /// Registers a function as the behavior [id]; see [FunctionBehavior].
  void registerFn(
    String id,
    Action Function(WorldView view, EntityId self) decide,
  ) => register(id, FunctionBehavior(decide));

  Behavior resolve(String id) {
    final behavior = _behaviors[id];
    if (behavior == null) {
      throw ArgumentError(
        'No Behavior registered for id "$id". Call registry.register() first.',
      );
    }
    return behavior;
  }

  bool has(String id) => _behaviors.containsKey(id);
}
