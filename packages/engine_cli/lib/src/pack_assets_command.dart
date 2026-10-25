import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:path/path.dart' as p;

import 'image_codec.dart';

/// Thin CLI adapter over `asset.pack`: keeps the historical `game_agent pack-assets`
/// invocation while the packing algorithm and proposal live in `engine_core`.
class PackAssetsCommand extends Command<int> {
  @override
  final name = 'pack-assets';
  @override
  final description =
      'Pack every image under a directory into one sprite sheet + manifest, '
      'for GameConfig.packedAtlasId (run before flutter run/build).';

  /// Bounds packing retries; injectable so exhaustion can be tested with
  /// small images instead of allocating an impractically large atlas.
  final int maxPackingAttempts;

  PackAssetsCommand({this.maxPackingAttempts = 20}) {
    argParser
      ..addOption(
        'input',
        abbr: 'i',
        help:
            'Directory to scan recursively for images (.png/.jpg/.jpeg/.bmp/.gif).',
      )
      ..addOption(
        'output-image',
        abbr: 'o',
        defaultsTo: 'assets/packed/atlas.png',
        help: 'Where to write the packed sprite sheet PNG.',
      )
      ..addOption(
        'output-manifest',
        abbr: 'm',
        help:
            'Where to write the region manifest JSON. Defaults to '
            '--output-image with a .json extension.',
      )
      ..addOption(
        'padding',
        defaultsTo: '2',
        help:
            'Transparent pixels left between packed regions, to avoid '
            'texture-filtering bleed between adjacent sprites at runtime.',
      )
      ..addOption(
        'max-width',
        defaultsTo: '2048',
        help:
            'Starting width hint for the packer (it grows the sheet as '
            'needed if this turns out too small for everything to fit) — '
            'not a hard cap on the final sheet width.',
      )
      ..addOption(
        'scales',
        defaultsTo: '1.0',
        help:
            'Comma-separated resolution tiers to pack, e.g. "1.0,0.5,0.25" '
            '-- each source image is resized (before packing, so the packer '
            'still sees real post-resize dimensions) and written to its own '
            'sheet + manifest pair.',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final inputPath = args['input'] as String?;
    if (inputPath == null) {
      stderr.writeln(
        'Error: missing --input, e.g. `game_agent pack-assets --input assets/images`',
      );
      return 1;
    }

    final inputDir = Directory(inputPath);
    if (!inputDir.existsSync()) {
      stderr.writeln('Error: ${inputDir.path} does not exist.');
      return 1;
    }

    // Resolve paths relative to cwd into an ephemeral project root that is the
    // common ancestor of input and outputs, so the sandbox can touch them.
    final outputImagePath = p.normalize(
      p.absolute(args['output-image'] as String),
    );
    final outputManifestPath = p.normalize(
      p.absolute(
        (args['output-manifest'] as String?) ??
            defaultManifestPath(outputImagePath),
      ),
    );
    final inputAbs = p.normalize(p.absolute(inputPath));
    final root = _commonRoot([inputAbs, outputImagePath, outputManifestPath]);

    final padding = int.tryParse(args['padding'] as String);
    final maxWidth = int.tryParse(args['max-width'] as String);
    if (padding == null || padding < 0) {
      stderr.writeln('Error: --padding must be a non-negative integer.');
      return 1;
    }
    if (maxWidth == null || maxWidth < 1) {
      stderr.writeln('Error: --max-width must be a positive integer.');
      return 1;
    }

    final registry = buildRegistry();
    final ctx = OpContext(
      project: ProjectRoot(root),
      actor: 'cli',
      imageCodec: const PackageImageCodec(),
    );
    final result = await registry.call(
      'asset.pack',
      {
        'input': p.relative(inputAbs, from: root),
        'outputImage': p.relative(outputImagePath, from: root),
        'outputManifest': p.relative(outputManifestPath, from: root),
        'padding': padding,
        'maxWidth': maxWidth,
        'scales': args['scales'] as String,
        'maxAttempts': maxPackingAttempts,
        'apply': true,
      },
      ctx,
    );
    if (!result.ok) {
      final err = result.error!;
      // Preserve the historical StateError for grow-exhaustion so existing tests
      // and scripts that catch it keep working.
      if (err.code == ErrorCode.internal &&
          err.message.contains('grow attempts')) {
        throw StateError(err.message);
      }
      stderr.writeln('Error: ${err.message}');
      if (err.hint != null) stderr.writeln(err.hint);
      // Historical pack-assets always exited 1 on failure (not sysexits codes).
      return 1;
    }
    final data = result.data as Map;
    for (final tier in (data['tiers'] as List).cast<Map>()) {
      stdout.writeln(
        '${tier['image']}: packed ${data['images']} images into '
        '${tier['width']}x${tier['height']} '
        '(manifest: ${tier['manifest']})',
      );
    }
    return 0;
  }
}

String _commonRoot(List<String> paths) {
  final parts = [
    for (final path in paths) p.split(p.normalize(path)),
  ];
  final first = parts.first;
  var i = 0;
  while (i < first.length) {
    if (parts.any((x) => i >= x.length || x[i] != first[i])) break;
    i++;
  }
  if (i == 0) return p.separator;
  return p.joinAll(first.sublist(0, i));
}
