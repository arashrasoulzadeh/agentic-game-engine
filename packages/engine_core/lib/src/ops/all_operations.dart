import 'groups/engine_ops.dart';
import 'groups/undo_ops.dart';
import 'operation.dart';
import 'registry.dart';
import 'safety.dart';

/// Builds the registry with every operation of this version. Later phases append their groups here.
OperationRegistry buildRegistry({ProposalFinisher? finisher}) {
  late final OperationRegistry registry;
  final ops = <Operation>[
    ...engineOperations(() => registry),
    ...undoOperations(),
  ];
  registry = OperationRegistry(
    ops,
    finisher: finisher ?? SafetyPipeline().finish,
  );
  return registry;
}
