import 'dart:io';

import 'package:engine_api/engine_api.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--version') || args.contains('-v')) {
    stdout.writeln('engine_api $engineApiVersion');
    return;
  }
  stderr.writeln('engine_api $engineApiVersion: not implemented yet (see engine_mcp.md).');
  exitCode = 64;
}
