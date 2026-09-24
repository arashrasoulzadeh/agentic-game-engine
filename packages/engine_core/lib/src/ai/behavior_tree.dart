import 'dart:collection';

import '../ecs/behavior.dart';
import '../ecs/action.dart';
import '../ecs/entity.dart';
import '../ecs/world_view.dart';
import '../ecs/world.dart';
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
class BTRepeater extends BTNode {
  final BTNode child;
  final int? count;

  BTRepeater({required this.child, this.count, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final currentCount = context.get<int>('${id}_count') ?? 0;

    if (count != null && currentCount >= count!) {
      context.set('${id}_count', 0);
      return BTStatus.success;
    }

    final status = child.tick(context);
    if (status == BTStatus.running) {
      return BTStatus.running;
    }

    context.set('${id}_count', currentCount + 1);

    // If child failed and we have more iterations, keep going
    if (status == BTStatus.failure && (count == null || currentCount + 1 < count!)) {
      return BTStatus.running;
    }

    return status;
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
class BTWait extends BTNode {
  final double duration;

  BTWait({required this.duration, String? id}) : super(id: id);

  @override
  BTStatus tick(BTContext context) {
    final elapsed = context.get<double>('${id}_elapsed') ?? 0.0;
    // Assume fixed timestep of ~1/60 for now - real implementation would need dt from context
    const dt = 1.0 / 60.0;

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

    final blackboard = aiState.memory['_bt_blackboard'] as Map<String, dynamic>? ?? <String, dynamic>{};
    aiState.memory['_bt_blackboard'] = blackboard;

    final context = BTContext(view, entity, blackboard: blackboard)
      ..set('_bt_registry', registry);

    root.tick(context);
  }
}