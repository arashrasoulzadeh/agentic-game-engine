/// The operation registry: every studio command, engine function and project function as one typed, documented
/// operation that the CLI, the MCP server and the HTTP/JSON-RPC API all bind to (see `engine_mcp.md`).
///
/// A separate entry point, like `engine_core_io.dart`: it uses `dart:io` (files, symlink checks) and is not part
/// of `engine_core.dart`, which stays web-compilable.
library;

export 'src/ops/all_operations.dart';
export 'src/ops/context.dart';
export 'src/ops/files.dart';
export 'src/ops/groups/engine_ops.dart' show allInputSchemas, engineOperations;
export 'src/ops/groups/undo_ops.dart' show undoOperations;
export 'src/ops/json_schema.dart';
export 'src/ops/operation.dart';
export 'src/ops/param.dart';
export 'src/ops/paths.dart';
export 'src/ops/registry.dart';
export 'src/ops/result.dart';
export 'src/ops/safety.dart';
export 'src/ops/undo_log.dart';
export 'src/ops/project/find_replace.dart';
export 'src/ops/project/git_status.dart';
export 'src/ops/project/project_search.dart';
export 'src/ops/project/project_tree.dart';
export 'src/ops/project/studio_project.dart';
export 'src/ops/release_plan.dart';
export 'src/ops/level_check.dart';
export 'src/ops/groups/project_ops.dart' show projectOperations;
export 'src/ops/groups/idle_ops.dart' show idleOperations;
export 'src/ops/groups/asset_ops.dart' show assetOperations;
export 'src/ops/groups/graph_ops.dart' show graphOperations, checkGraphText;
export 'src/ops/groups/problems_ops.dart' show problemOperations;
export 'src/ops/groups/level_lint_ops.dart' show levelLintOperations;
export 'src/ops/groups/level_write_ops.dart' show levelWriteOperations;
export 'src/ops/groups/prefab_ops.dart' show prefabOperations;
export 'src/ops/groups/tmx_ops.dart' show tmxOperations;
export 'src/ops/groups/world_ops.dart' show worldOperations;
export 'src/ops/world_sandbox.dart';
export 'src/ops/groups/save_ops.dart' show saveOperations;
export 'src/ops/groups/level_ops.dart'
    show levelReadOperations, levelText, parseLevel, knownComponents;
export 'src/ops/groups/release_ops.dart' show releaseOperations;
export 'src/ops/groups/schema_ops.dart' show schemaOperations;
export 'src/ops/project/asset_index.dart';
export 'src/ops/project/atlas_catalog.dart';
export 'src/ops/project/project_symbols.dart';
