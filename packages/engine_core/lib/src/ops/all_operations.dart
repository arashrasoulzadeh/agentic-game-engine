import 'groups/engine_ops.dart';
import 'groups/idle_ops.dart';
import 'groups/level_ops.dart';
import 'groups/project_ops.dart';
import 'groups/release_ops.dart';
import 'groups/schema_ops.dart';
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
    ...schemaOperations(),
    ...idleOperations(),
    ...releaseOperations(),
    ...undoOperations(),
  ];
  registry = OperationRegistry(
    ops,
    finisher: finisher ?? SafetyPipeline().finish,
  );
  return registry;
}
