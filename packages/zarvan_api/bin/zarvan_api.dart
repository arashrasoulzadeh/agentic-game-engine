import 'dart:io';

import 'package:zarvan_api/zarvan_api.dart';

Future<void> main(List<String> args) async {
  exitCode = await runServer(args);
}
