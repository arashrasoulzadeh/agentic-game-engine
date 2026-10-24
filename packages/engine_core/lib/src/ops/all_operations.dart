import 'groups/engine_ops.dart';
import 'operation.dart';
import 'registry.dart';

/// Builds the registry with every operation of this version. Later phases append their groups here.
OperationRegistry buildRegistry({ProposalFinisher? finisher}) {
  late final OperationRegistry registry;
  final ops = <Operation>[...engineOperations(() => registry)];
  registry = OperationRegistry(ops, finisher: finisher);
  return registry;
}
