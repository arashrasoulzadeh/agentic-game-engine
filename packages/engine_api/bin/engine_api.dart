import 'dart:io';

import 'package:engine_api/engine_api.dart';

Future<void> main(List<String> args) async {
  exitCode = await runServer(args);
}
