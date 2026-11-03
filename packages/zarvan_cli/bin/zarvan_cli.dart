import 'dart:io';

import 'package:zarvan_cli/src/webp_transform.dart';

/// Flutter asset transformer (`flutter: assets: - path: ... transformers:`):
/// `dart run zarvan_cli --input=<in> --output=<out>`. Flutter derives the
/// command from `- package: zarvan_cli`, which runs `bin/zarvan_cli.dart`;
/// the user-facing CLI is `bin/zarvan.dart`.
///
/// Converts PNGs to lossless WebP while the app is built, leaving the source
/// art untouched. See `transformImage` for the fallbacks.
int main(List<String> args) {
  String? input, output;
  for (final a in args) {
    if (a.startsWith('--input=')) input = a.substring(8);
    if (a.startsWith('--output=')) output = a.substring(9);
  }
  if (input == null || output == null) {
    stderr.writeln('usage: dart run zarvan_cli --input=<file> --output=<file>');
    return 64;
  }
  transformImage(input, output);
  return 0;
}
