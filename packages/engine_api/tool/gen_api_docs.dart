// Regenerates docs/reference/operations.md (default) or transports.md (--transports).
//
//   dart run tool/gen_api_docs.dart > ../../docs/reference/operations.md
//   dart run tool/gen_api_docs.dart --transports > ../../docs/reference/transports.md
import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:engine_core/engine_core_ops.dart';

void main(List<String> args) {
  final registry = buildRegistry();
  if (args.contains('--transports')) {
    stdout.write(renderTransportsQuickStart(registry));
  } else {
    stdout.write(renderOperationsReference(registry));
  }
}
