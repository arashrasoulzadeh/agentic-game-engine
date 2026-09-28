import '../ecs/behavior.dart';
import '../ecs/action.dart';
import '../ecs/entity.dart';
import '../ecs/world_view.dart';
import '../ecs/world.dart';
import '../ecs/system.dart';
import '../ai/ai_state.dart';

/// Base class for all behavior tree nodes.
abstract class BTNode {
  final String? id;

  BTNode({this.id});

  /// Runs this node, returning its status.
  BTStatus tick(BTContext context);

  /// Serializes this node to JSON.
  Map<String, dynamic> toJson();

  /// Creates a node from JSON.
  static BTNode fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    switch (type) {
      case 'sequence':
        return BTSequence.fromJson(json);
      case 'selector':
        return BTSelector.fromJson(json);
      case 'parallel':
        return BTParallel.fromJson(json);
      case 'inverter':
        return BTInverter.fromJson(json);
      case 'repeater':
        return BTRepeater.fromJson(json);
      case 'succeeder':
        return BTSucceeder.fromJson(json);
      case 'failer':
        return BTFailer.fromJson(json);
      case 'leaf':
        return BTLeaf.fromJson(json);
      case 'wait':
        return BTWait.fromJson(json);
      case 'cooldown':
        return BTCooldown.fromJson(json);
      case 'randomSelector':
        return BTRandomSelector.fromJson(json);
      case 'randomSequence':
        return BTRandomSequence.fromJson(json);
      case 'untilSuccess':
        return BTUntilSuccess.fromJson(json);
      case 'untilFailure':
        return BTUntilFailure.fromJson(json);
      case 'timeout':
        return BTTimeout.fromJson(json);
      case 'throttle':
        return BTThrottle.fromJson(json);
      case 'timer':
        return BTTimer.fromJson(json);
      default:
        throw ArgumentError('Unknown BT node type: $type');
    }
  }
}

/// Status returned by a behavior tree node after ticking.
enum BTStatus {
  success,
  failure,
  running,
}

/// Context passed to behavior tree nodes during execution.
/// Holds the WorldView, entity ID, and a blackboard for storing state.
class BTContext {
  final WorldView view;
  final EntityId entity;
  final Map<String, dynamic> blackboard;

  BTContext(this.view, this.entity, {Map<String, dynamic>? blackboard})
      : blackboard = blackboard ?? <String, dynamic>{};

  T? get<T>(String key) => blackboard[key] as T?;
  void set<T>(String key, T value) => blackboard[key] = value;
}

/// Composite node that ticks children in order until one fails or all succeed.
class BTSequence extends BTNode {
  final List<BTNode> children;

  BTSequence({required this.children, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final runningIndex = context.get<int>('${id}_runningIndex') ?? 0;
    for (var i = runningIndex; i < children.length; i++) {
      final status = children[i].tick(context);
      if (status == BTStatus.failure) {
        context.set('${id}_runningIndex', 0);
        return BTStatus.failure;
      }
      if (status == BTStatus.running) {
        context.set('${id}_runningIndex', i);
        return BTStatus.running;
      }
    }
    context.set('${id}_runningIndex', 0);
    return BTStatus.success;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'sequence',
        'id': id,
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory BTSequence.fromJson(Map<String, dynamic> json) => BTSequence(
        id: json['id'] as String?,
        children: (json['children'] as List)
            .map((c) => BTNode.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// Composite node that ticks children in order until one succeeds or all fail.
class BTSelector extends BTNode {
  final List<BTNode> children;

  BTSelector({required this.children, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final runningIndex = context.get<int>('${id}_runningIndex') ?? 0;
    for (var i = runningIndex; i < children.length; i++) {
      final status = children[i].tick(context);
      if (status == BTStatus.success) {
        context.set('${id}_runningIndex', 0);
        return BTStatus.success;
      }
      if (status == BTStatus.running) {
        context.set('${id}_runningIndex', i);
        return BTStatus.running;
      }
    }
    context.set('${id}_runningIndex', 0);
    return BTStatus.failure;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'selector',
        'id': id,
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory BTSelector.fromJson(Map<String, dynamic> json) => BTSelector(
        id: json['id'] as String?,
        children: (json['children'] as List)
            .map((c) => BTNode.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// Composite node that ticks all children each tick.
/// Succeeds if [requiredSuccess] children succeed; fails if [children.length - requiredSuccess + 1] fail.
class BTParallel extends BTNode {
  final List<BTNode> children;
  final int requiredSuccess;

  BTParallel({required this.children, this.requiredSuccess = 1, String? id})
      : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    var successCount = 0;
    var failureCount = 0;
    var anyRunning = false;

    for (final child in children) {
      final status = child.tick(context);
      switch (status) {
        case BTStatus.success:
          successCount++;
          break;
        case BTStatus.failure:
          failureCount++;
          break;
        case BTStatus.running:
          anyRunning = true;
          break;
      }
    }

    if (successCount >= requiredSuccess) return BTStatus.success;
    if (failureCount > children.length - requiredSuccess) return BTStatus.failure;
    if (anyRunning) return BTStatus.running;
    return BTStatus.failure;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'parallel',
        'id': id,
        'requiredSuccess': requiredSuccess,
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory BTParallel.fromJson(Map<String, dynamic> json) => BTParallel(
        id: json['id'] as String?,
        requiredSuccess: (json['requiredSuccess'] as num?)?.toInt() ?? 1,
        children: (json['children'] as List)
            .map((c) => BTNode.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// Decorator that inverts the child's result (success <-> failure).
class BTInverter extends BTNode {
  final BTNode child;

  BTInverter({required this.child, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final status = child.tick(context);
    switch (status) {
      case BTStatus.success:
        return BTStatus.failure;
      case BTStatus.failure:
        return BTStatus.success;
      case BTStatus.running:
        return BTStatus.running;
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'inverter',
        'id': id,
        'child': child.toJson(),
      };

  factory BTInverter.fromJson(Map<String, dynamic> json) => BTInverter(
        id: json['id'] as String?,
        child: BTNode.fromJson(json['child'] as Map<String, dynamic>),
      );
}

/// Decorator that repeats the child [count] times (or forever if null).
/// If the child returns success/failure instantly (not running), this will
/// loop and run the child again in the same tick until the count is reached
/// or the child returns running.
class BTRepeater extends BTNode {
  final BTNode child;
  final int? count;

  BTRepeater({required this.child, this.count, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    var currentCount = context.get<int>('${id}_count') ?? 0;

    // If already completed (finite count), stay in success state
    if (count != null && currentCount >= count!) {
      return BTStatus.success;
    }

    BTStatus status = BTStatus.failure;
    while (true) {
      status = child.tick(context);
      if (status == BTStatus.running) {
        return BTStatus.running;
      }

      currentCount++;
      context.set('${id}_count', currentCount);

      // If we've reached the count (finite), stop
      if (count != null && currentCount >= count!) {
        return BTStatus.success;
      }

      // If child failed:
      // - With finite count: return running to continue next tick
      // - With infinite count (null): stop and return failure (repeat until failure)
      if (status == BTStatus.failure) {
        if (count == null) {
          // Infinite repeater stops on failure
          context.set('${id}_count', 0);
          return BTStatus.failure;
        }
        // Finite count: return running to continue next tick
        return BTStatus.running;
      }

      // Child succeeded:
      // - With finite count: continue looping internally (already handled by count check above)
      // - With infinite count: continue looping internally (repeat until failure)
      if (count == null) {
        // Infinite repeater: continue looping on success
        continue;
      }
      // Finite count but not reached limit: return running to continue next tick
      return BTStatus.running;
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'repeater',
        'id': id,
        'count': count,
        'child': child.toJson(),
      };

  factory BTRepeater.fromJson(Map<String, dynamic> json) => BTRepeater(
        id: json['id'] as String?,
        count: (json['count'] as num?)?.toInt(),
        child: BTNode.fromJson(json['child'] as Map<String, dynamic>),
      );
}

/// Decorator that always returns success regardless of child's result.
class BTSucceeder extends BTNode {
  final BTNode child;

  BTSucceeder({required this.child, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    child.tick(context);
    return BTStatus.success;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'succeeder',
        'id': id,
        'child': child.toJson(),
      };

  factory BTSucceeder.fromJson(Map<String, dynamic> json) => BTSucceeder(
        id: json['id'] as String?,
        child: BTNode.fromJson(json['child'] as Map<String, dynamic>),
      );
}

/// Decorator that always returns failure regardless of child's result.
class BTFailer extends BTNode {
  final BTNode child;

  BTFailer({required this.child, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    child.tick(context);
    return BTStatus.failure;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'failer',
        'id': id,
        'child': child.toJson(),
      };

  factory BTFailer.fromJson(Map<String, dynamic> json) => BTFailer(
        id: json['id'] as String?,
        child: BTNode.fromJson(json['child'] as Map<String, dynamic>),
      );
}

/// Leaf node that executes a registered [Behavior] by name.
/// The behavior is looked up from the BehaviorRegistry each tick.
class BTLeaf extends BTNode {
  final String behaviorId;

  BTLeaf({required this.behaviorId, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    // Get the behavior from the registry stored in context
    final registry = context.get<BehaviorRegistry>('_bt_registry');
    if (registry == null) {
      throw StateError('BehaviorRegistry not found in BTContext. '
          'Did you forget to wrap the tree in a BehaviorTreeBehavior?');
    }

    final behavior = registry.resolve(behaviorId);
    final action = behavior.decide(context.view, context.entity);
    action.apply(context.view.world); // Apply directly to world
    
    // Check if the action signals failure
    if (action is FailureAction) {
      return BTStatus.failure;
    }
    return BTStatus.success;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'leaf',
        'id': id,
        'behaviorId': behaviorId,
      };

  factory BTLeaf.fromJson(Map<String, dynamic> json) => BTLeaf(
        id: json['id'] as String?,
        behaviorId: json['behaviorId'] as String,
      );
}

/// Leaf node that waits for [duration] seconds, then returns success.
/// Uses the dt from context for accurate timing.
class BTWait extends BTNode {
  final double duration;

  BTWait({required this.duration, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final elapsed = context.get<double>('${id}_elapsed') ?? 0.0;
    // Use dt from context if available, otherwise assume 1/60
    final dt = context.get<double>('_dt') ?? 1.0 / 60.0;

    final newElapsed = elapsed + dt;
    if (newElapsed >= duration) {
      context.set('${id}_elapsed', 0.0);
      return BTStatus.success;
    }
    context.set('${id}_elapsed', newElapsed);
    return BTStatus.running;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'wait',
        'id': id,
        'duration': duration,
      };

  factory BTWait.fromJson(Map<String, dynamic> json) => BTWait(
        id: json['id'] as String?,
        duration: (json['duration'] as num).toDouble(),
      );
}

/// Leaf node that executes a registered [Behavior] by name with a cooldown.
/// After the behavior runs successfully, it enters a cooldown period before it can run again.
class BTCooldown extends BTNode {
  final String behaviorId;
  final double cooldownDuration;

  BTCooldown({required this.behaviorId, required this.cooldownDuration, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final registry = context.get<BehaviorRegistry>('_bt_registry');
    if (registry == null) {
      throw StateError('BehaviorRegistry not found in BTContext.');
    }

    final lastRun = context.get<double>('${id}_lastRun') ?? -cooldownDuration;
    final now = context.get<double>('_time') ?? 0.0;

    if (now - lastRun < cooldownDuration) {
      return BTStatus.running;
    }

    final behavior = registry.resolve(behaviorId);
    final action = behavior.decide(context.view, context.entity);
    action.apply(context.view.world);

    context.set('${id}_lastRun', context.get<double>('_time') ?? 0.0);
    return BTStatus.success;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'cooldown',
        'id': id,
        'behaviorId': behaviorId,
        'cooldownDuration': cooldownDuration,
      };

  factory BTCooldown.fromJson(Map<String, dynamic> json) => BTCooldown(
        id: json['id'] as String?,
        behaviorId: json['behaviorId'] as String,
        cooldownDuration: (json['cooldownDuration'] as num).toDouble(),
      );
}

/// Decorator that runs its child in a random order each tick (for Selector-like behavior).
class BTRandomSelector extends BTNode {
  final List<BTNode> children;

  BTRandomSelector({required this.children, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final shuffled = List<BTNode>.from(children)..shuffle();
    for (final child in shuffled) {
      final status = child.tick(context);
      if (status == BTStatus.success) {
        return BTStatus.success;
      }
      if (status == BTStatus.running) {
        return BTStatus.running;
      }
    }
    return BTStatus.failure;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'randomSelector',
        'id': id,
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory BTRandomSelector.fromJson(Map<String, dynamic> json) => BTRandomSelector(
        id: json['id'] as String?,
        children: (json['children'] as List)
            .map((c) => BTNode.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// Decorator that runs its child in a random order each tick (for Sequence-like behavior).
class BTRandomSequence extends BTNode {
  final List<BTNode> children;

  BTRandomSequence({required this.children, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final shuffled = List<BTNode>.from(children)..shuffle();
    for (final child in shuffled) {
      final status = child.tick(context);
      if (status == BTStatus.failure) {
        return BTStatus.failure;
      }
      if (status == BTStatus.running) {
        return BTStatus.running;
      }
    }
    return BTStatus.success;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'randomSequence',
        'id': id,
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory BTRandomSequence.fromJson(Map<String, dynamic> json) => BTRandomSequence(
        id: json['id'] as String?,
        children: (json['children'] as List)
            .map((c) => BTNode.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// Decorator that runs its child until it returns success, then returns success.
/// If the child returns failure, it keeps retrying (returns running).
class BTUntilSuccess extends BTNode {
  final BTNode child;

  BTUntilSuccess({required this.child, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final status = child.tick(context);
    if (status == BTStatus.success) {
      return BTStatus.success;
    }
    return BTStatus.running;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'untilSuccess',
        'id': id,
        'child': child.toJson(),
      };

  factory BTUntilSuccess.fromJson(Map<String, dynamic> json) => BTUntilSuccess(
        id: json['id'] as String?,
        child: BTNode.fromJson(json['child'] as Map<String, dynamic>),
      );
}

/// Decorator that runs its child until it returns failure, then returns failure.
/// If the child returns success, it keeps retrying (returns running).
class BTUntilFailure extends BTNode {
  final BTNode child;

  BTUntilFailure({required this.child, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final status = child.tick(context);
    if (status == BTStatus.failure) {
      return BTStatus.failure;
    }
    return BTStatus.running;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'untilFailure',
        'id': id,
        'child': child.toJson(),
      };

  factory BTUntilFailure.fromJson(Map<String, dynamic> json) => BTUntilFailure(
        id: json['id'] as String?,
        child: BTNode.fromJson(json['child'] as Map<String, dynamic>),
      );
}

/// Decorator that runs its child for a maximum duration, then returns failure (timeout).
class BTTimeout extends BTNode {
  final BTNode child;
  final double timeoutDuration;

  BTTimeout({required this.child, required this.timeoutDuration, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final elapsed = context.get<double>('${id}_elapsed') ?? 0.0;
    final dt = context.get<double>('_dt') ?? 1.0 / 60.0;

    final newElapsed = elapsed + dt;
    if (newElapsed >= timeoutDuration) {
      context.set('${id}_elapsed', 0.0);
      return BTStatus.failure;
    }
    context.set('${id}_elapsed', newElapsed);

    return child.tick(context);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'timeout',
        'id': id,
        'timeoutDuration': timeoutDuration,
        'child': child.toJson(),
      };

  factory BTTimeout.fromJson(Map<String, dynamic> json) => BTTimeout(
        id: json['id'] as String?,
        timeoutDuration: (json['timeoutDuration'] as num).toDouble(),
        child: BTNode.fromJson(json['child'] as Map<String, dynamic>),
      );
}

/// Decorator that limits the number of times its child can run per tick.
class BTThrottle extends BTNode {
  final BTNode child;
  final int maxRunsPerTick;

  BTThrottle({required this.child, this.maxRunsPerTick = 1, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    var runCount = context.get<int>('${id}_runCount') ?? 0;
    if (runCount >= maxRunsPerTick) {
      return BTStatus.running;
    }
    runCount++;
    context.set('${id}_runCount', runCount);
    return child.tick(context);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'throttle',
        'id': id,
        'maxRunsPerTick': maxRunsPerTick,
        'child': child.toJson(),
      };

  factory BTThrottle.fromJson(Map<String, dynamic> json) => BTThrottle(
        id: json['id'] as String?,
        maxRunsPerTick: (json['maxRunsPerTick'] as num?)?.toInt() ?? 1,
        child: BTNode.fromJson(json['child'] as Map<String, dynamic>),
      );
}

/// Timer node that succeeds after [duration] seconds, then resets.
/// Useful for timed behaviors.
class BTTimer extends BTNode {
  final double duration;
  final bool repeat;

  BTTimer({required this.duration, this.repeat = false, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final elapsed = context.get<double>('${id}_elapsed') ?? 0.0;
    final dt = context.get<double>('_dt') ?? 1.0 / 60.0;

    final newElapsed = elapsed + dt;
    if (newElapsed >= duration) {
      if (repeat) {
        context.set('${id}_elapsed', 0.0);
        return BTStatus.success;
      }
      context.set('${id}_elapsed', 0.0);
      return BTStatus.success;
    }
    context.set('${id}_elapsed', newElapsed);
    return BTStatus.running;
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': 'timer',
        'id': id,
        'duration': duration,
        'repeat': repeat,
      };

  factory BTTimer.fromJson(Map<String, dynamic> json) => BTTimer(
        id: json['id'] as String?,
        duration: (json['duration'] as num).toDouble(),
        repeat: json['repeat'] as bool? ?? false,
      );
}

/// Updates the context's time and dt values.
/// Should be called at the start of each tick by BehaviorTreeSystem.
class _UpdateTimeAction implements Action {
  final double time;
  final double dt;

  _UpdateTimeAction(this.time, this.dt);

  @override
  void apply(World world) {
    // No-op - time is set in context by BehaviorTreeSystem
  }
}

/// Behavior that executes a behavior tree.
/// This wraps a BTNode and implements the standard Behavior interface.
class BehaviorTreeBehavior implements Behavior {
  final BTNode root;
  final BehaviorRegistry registry;

  BehaviorTreeBehavior({required this.root, required this.registry});

  @override
  Action decide(WorldView view, EntityId self) {
    // Store registry and dt in context for nodes to access
    // We use a custom action that runs the tree
    return _RunTreeAction(root, registry, view, self);
  }
}

/// System that runs behavior trees stored in AIState.memory['_bt_root'].
/// For each entity with AIState and a '_bt_root' key, it executes the tree.
class BehaviorTreeSystem implements System {
  final BehaviorRegistry registry;

  BehaviorTreeSystem(this.registry);

  @override
  String get name => 'behaviorTree';

  @override
  void update(World world, double dt) {
    final states = world.storeOf<AIState>();
    for (var i = 0; i < states.length; i++) {
      final entity = states.entityAt(i);
      final state = states.denseAt(i);

      final rootJson = (state.memory['_bt_root'] as Map?)?.cast<String, dynamic>();
      if (rootJson == null) continue;

      final root = BTNode.fromJson(rootJson);

      final rawBlackboard = state.memory['_bt_blackboard'];
      final blackboard = (rawBlackboard as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
      state.memory['_bt_blackboard'] = blackboard;

      final view = WorldView(world);
      final context = BTContext(view, entity, blackboard: blackboard)
        ..set('_bt_registry', registry);

      root.tick(context);
    }
  }
}

/// Action that runs the behavior tree for one tick.
class _RunTreeAction implements Action {
  final BTNode root;
  final BehaviorRegistry registry;
  final WorldView view;
  final EntityId entity;

  _RunTreeAction(this.root, this.registry, this.view, this.entity);

  @override
  void apply(World world) {
    // We need to store per-entity blackboard state
    // Use AIState.memory as the blackboard
    final aiState = world.storeOf<AIState>().get(entity);
    if (aiState == null) return;

    final rawBlackboard = aiState.memory['_bt_blackboard'];
    final blackboard = (rawBlackboard as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    aiState.memory['_bt_blackboard'] = blackboard;

    final context = BTContext(view, entity, blackboard: blackboard)
      ..set('_bt_registry', registry);

    root.tick(context);
  }
}