import 'groups/animation_ops.dart';
import 'groups/asset_ops.dart';
import 'groups/engine_ops.dart';
import 'groups/graph_ops.dart';
import 'groups/i18n_ops.dart';
import 'groups/idle_ops.dart';
import 'groups/level_lint_ops.dart';
import 'groups/level_ops.dart';
import 'groups/level_write_ops.dart';
import 'groups/prefab_ops.dart';
import 'groups/problems_ops.dart';
import 'groups/project_ops.dart';
import 'groups/release_ops.dart';
import 'groups/save_ops.dart';
import 'groups/schema_ops.dart';
import 'groups/strategy_ops.dart';
import 'groups/tmx_ops.dart';
import 'groups/world_ops.dart';
import 'groups/undo_ops.dart';
import 'operation.dart';
import 'registry.dart';
import 'safety.dart';

/// Builds the registry with every operation of this version. Later phases append their groups here.
OperationRegistry buildRegistry({ProposalFinisher? finisher}) {
  late final OperationRegistry registry;
  final ops = <Operation>[
    ...engineOperations(() => registry),
    ...projectOperations(),
    ...levelReadOperations(),
    ...assetOperations(),
    ...animationOperations(),
    ...graphOperations(),
    ...problemOperations(),
    ...levelLintOperations(),
    ...levelWriteOperations(),
    ...prefabOperations(),
    ...tmxOperations(),
    ...worldOperations(),
    ...saveOperations(),
    ...schemaOperations(),
    ...idleOperations(),
    ...i18nOperations(),
    ...strategyOperations(),
    ...releaseOperations(),
    ...undoOperations(),
  ];
  registry = OperationRegistry(
    ops,
    finisher: finisher ?? SafetyPipeline().finish,
  );
  return registry;
}
