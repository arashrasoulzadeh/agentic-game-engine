/// The operation registry: every studio command, engine function and project function as one typed, documented
/// operation that the CLI, the MCP server and the HTTP/JSON-RPC API all bind to (see `engine_mcp.md`).
///
/// A separate entry point, like `engine_core_io.dart`: it uses `dart:io` (files, symlink checks) and is not part
/// of `engine_core.dart`, which stays web-compilable.
library;

export 'src/ops/all_operations.dart';
export 'src/ops/context.dart';
export 'src/ops/files.dart';
export 'src/ops/groups/engine_ops.dart' show allInputSchemas;
export 'src/ops/json_schema.dart';
export 'src/ops/operation.dart';
export 'src/ops/param.dart';
export 'src/ops/paths.dart';
export 'src/ops/registry.dart';
export 'src/ops/result.dart';
