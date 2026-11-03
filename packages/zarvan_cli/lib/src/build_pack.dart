import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import 'pack_assets_command.dart';

/// Packs the project's sprite atlas when `assets/game_config.json` asks for it
/// (`packedAtlasSource` + `packedAtlasImage`), so builds produce the atlas and
/// nobody has to remember to run `zarvan pack-assets` first.
///
/// Returns null when the project has no packing configured, `0` after a
/// successful pack, or the failing exit code. With [dryRun] nothing is written
/// and the step is only reported.
Future<int?> packConfiguredAtlas(
  String projectDir, {
  bool dryRun = false,
  void Function(String) log = print,
}) async {
  final file = File(p.join(projectDir, 'assets', 'game_config.json'));
  if (!file.existsSync()) return null;
  final Object? json;
  try {
    json = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return null;
  }
  if (json is! Map) return null;
  final source = json['packedAtlasSource'];
  final image = json['packedAtlasImage'];
  final manifest = json['packedAtlasManifest'];
  if (source is! String || image is! String) return null;

  final args = [
    'pack-assets',
    '--input',
    p.join(projectDir, source),
    '--output-image',
    p.join(projectDir, image),
    if (manifest is String) ...[
      '--output-manifest',
      p.join(projectDir, manifest),
    ],
  ];
  if (dryRun) {
    log('Would pack $source -> $image');
    return 0;
  }
  log('Packing $source -> $image');
  final runner = CommandRunner<int>('zarvan', 'build step')
    ..addCommand(PackAssetsCommand());
  return await runner.run(args) ?? 0;
}
