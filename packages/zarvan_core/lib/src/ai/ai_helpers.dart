import 'dart:math' as math;

import '../ecs/action.dart';
import '../ecs/behavior.dart';
import '../ecs/entity.dart';
import '../ecs/name.dart';
import '../ecs/world.dart';
import '../ecs/world_view.dart';
import '../physics/position.dart';
import 'ai_state.dart';
import 'behavior_tree.dart';

/// Shortcuts for pointing an entity at a behavior, instead of building an
/// [AIState] by hand.
extension WorldAI on World {
  /// Makes [entity] run the behavior registered as [id], replacing whatever it
  /// ran before. The entity's memory is cleared unless [keepMemory] (a new
  /// behavior usually should not inherit the old one's scratch data).
  ///
  /// Pass [behaviors] to check [id] now: an unknown id then throws an
  /// [ArgumentError] here, rather than later inside `AISystem` mid-step.
  /// Throws [StateError] if [entity] is not alive.
  void setBehavior(
    EntityId entity,
    String id, {
    BehaviorRegistry? behaviors,
    bool keepMemory = false,
  }) {
    if (behaviors != null && !behaviors.has(id)) behaviors.resolve(id);
    final old = getComponent<AIState>(entity);
    setComponent(entity, AIState(id, memory: keepMemory ? old?.memory : null));
  }

  /// Makes [entity] run [tree] every step under `AISystem`. The tree is
  /// registered in [behaviors] as [id] (default `tree@<entity>`), so ids are
  /// per entity: re-running replaces that entity's tree, and an id from a
  /// destroyed entity that gets reused is simply overwritten.
  void runTree(
    EntityId entity,
    BTNode tree, {
    required BehaviorRegistry behaviors,
    String? id,
  }) {
    final treeId = id ?? 'tree@$entity';
    behaviors.register(
      treeId,
      BehaviorTreeBehavior(root: tree, registry: behaviors),
    );
    setBehavior(entity, treeId);
  }
}

/// Yes/no questions a tree can ask, registered as behaviors: a leaf that
/// succeeds when the test is true and fails when it is false, so conditions
/// compose with `BT.sequence`/`BT.selector` and need no new node type.
///
/// ```dart
/// behaviors.registerInRange('playerNear', target: 'player', range: 80);
/// final tree = BT.selector([
///   BT.sequence([BT.leaf('playerNear'), BT.leaf('attack')]),
///   BT.leaf('patrol'),
/// ]);
/// ```
extension BehaviorConditions on BehaviorRegistry {
  /// Registers [test] as the condition [id]. It sees the same read-only
  /// [WorldView] as any behavior.
  void registerCondition(
    String id,
    bool Function(WorldView view, EntityId self) test,
  ) => registerFn(
    id,
    (view, self) =>
        test(view, self) ? const NoOpAction() : const FailureAction(),
  );

  /// True while the entity named [target] (see `world.find`) is within
  /// [range] of the one running the tree. False when either has no position or
  /// the target does not exist, so a missing player reads as "not near".
  void registerInRange(
    String id, {
    required String target,
    required double range,
  }) => registerCondition(id, (view, self) {
    final targetId = view.world.find(target);
    if (targetId == null) return false;
    final from = view.component<Position>(self);
    final to = view.component<Position>(targetId);
    if (from == null || to == null) return false;
    final dx = to.x - from.x, dy = to.y - from.y;
    return math.sqrt(dx * dx + dy * dy) <= range;
  });

  /// True while the entity running the tree has a [T] component.
  void registerHas<T>(String id) =>
      registerCondition(id, (view, self) => view.hasComponent<T>(self));
}
