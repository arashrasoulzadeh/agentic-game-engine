// Regenerates docs/reference/operations.md from the operation registry.
//
//   dart run tool/gen_api_docs.dart > ../../docs/reference/operations.md
import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:engine_core/engine_core_ops.dart';

void main() => stdout.write(renderOperationsReference(buildRegistry()));
