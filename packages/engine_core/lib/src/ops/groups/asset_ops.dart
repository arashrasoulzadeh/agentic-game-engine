import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../atlas_packer.dart';
import '../context.dart';
import '../image_codec.dart';
import '../operation.dart';
import '../param.dart';
import '../project/asset_index.dart';
import '../result.dart';

const _imageExtensions = {'.png', '.jpg', '.jpeg', '.bmp', '.gif'};

/// `asset.*`: what art and data a project contains, and packing atlases.
List<Operation> assetOperations() => [
  Operation(
    name: 'asset.index',
    summary:
        'List the project\'s atlases, images, audio, data files and prefabs.',
    description:
        'Atlases come from `assets/studio_atlases.json` (which gives them an id levels can use as `atlasId`) and from any '
        '`X.json` with a `regions` map next to `X.png` (what `game_agent pack-assets` / `asset.pack` writes). Images already '
        'part of an atlas are not listed again under `images`.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    handler: (ctx, a) {
      final index = AssetIndex.scan(ctx.project!.root);
      return OpOutcome.data({
        'atlases': [
          for (final at in index.atlases)
            {
              'id': at.id,
              'image': at.image,
              'manifest': at.manifest,
              'regions': at.regions.length,
              'declared': at.declared,
            },
        ],
        'images': index.images,
        'audio': index.audio,
        'data': index.data,
        'prefabs': index.prefabs,
      });
    },
  ),
  Operation(
    name: 'asset.atlas_regions',
    summary: 'The named regions of one atlas, with their rectangles.',
    description:
        'Look the atlas up by the id `asset.index` shows. Region objects are returned as the manifest stores them.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('atlas', ParamType.string, required: true, positional: true),
    ],
    errors: {
      ErrorCode.notFound: 'No such atlas, or its manifest is unreadable.',
    },
    handler: (ctx, a) {
      final id = a['atlas']! as String;
      final index = AssetIndex.scan(ctx.project!.root);
      final matches = index.atlases.where((x) => x.id == id).toList();
      if (matches.isEmpty) {
        throw OpError(
          ErrorCode.notFound,
          'No atlas "$id".',
          hint: 'asset.index lists the atlas ids.',
        );
      }
      final text = ctx.files.read(ctx.project!.resolve(matches.first.manifest));
      Map? regions;
      try {
        regions = (jsonDecode(text ?? '') as Map)['regions'] as Map?;
      } on Object {
        regions = null;
      }
      if (regions == null) {
        throw OpError(
          ErrorCode.notFound,
          'The manifest of "$id" has no regions.',
        );
      }
      return OpOutcome.data({
        'atlas': id,
        'image': matches.first.image,
        'regions': {
          for (final k in (regions.keys.map((e) => '$e').toList()..sort()))
            k: regions[k],
        },
      });
    },
  ),
  Operation(
    name: 'asset.pack',
    summary:
        'Pack every image under a directory into one sprite sheet + region manifest.',
    description:
        'Recursively loads images under `input`, MaxRects-packs them (with optional resolution tiers via '
        '`scales`), and proposes the PNG sheet(s) plus JSON manifest(s) that `SpriteAtlas.fromManifest` reads. '
        'Needs an [ImageCodec] on the context (`engine_cli` / `engine_api` inject one); without it returns '
        '`unsupported`. Same behaviour as `game_agent pack-assets`.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param(
        'input',
        ParamType.path,
        required: true,
        description: 'Directory of source images (scanned recursively).',
      ),
      Param(
        'outputImage',
        ParamType.path,
        defaultValue: 'assets/packed/atlas.png',
        cliFlag: 'output-image',
      ),
      Param(
        'outputManifest',
        ParamType.path,
        description: 'Defaults to outputImage with a .json extension.',
        cliFlag: 'output-manifest',
      ),
      Param('padding', ParamType.integer, min: 0, max: 64, defaultValue: 2),
      Param(
        'maxWidth',
        ParamType.integer,
        min: 1,
        max: 16384,
        defaultValue: 2048,
        cliFlag: 'max-width',
      ),
      Param(
        'scales',
        ParamType.string,
        defaultValue: '1.0',
        description: 'Comma-separated tiers, e.g. "1.0,0.5,0.25".',
      ),
      Param(
        'maxAttempts',
        ParamType.integer,
        min: 1,
        max: 100,
        defaultValue: 20,
        description: 'Grow-and-retry attempts before giving up.',
        cliFlag: 'max-attempts',
      ),
    ],
    errors: {
      ErrorCode.unsupported:
          'No ImageCodec is available on this server/CLI build.',
      ErrorCode.notFound: 'The input directory does not exist or has no images.',
      ErrorCode.validationFailed: 'Duplicate region names or bad scales.',
      ErrorCode.internal: 'The packer could not fit the images.',
    },
    handler: (ctx, a) => _packAssets(ctx, a),
  ),
];

OpOutcome _packAssets(OpContext ctx, Map<String, Object?> a) {
  final codec = ctx.imageCodec;
  if (codec == null) {
    throw OpError(
      ErrorCode.unsupported,
      'asset.pack needs an image codec.',
      hint: 'Use game_agent pack-assets, or start the API with an ImageCodec.',
    );
  }
  final project = ctx.project!;
  final inputRel = a['input']! as String;
  final inputAbs = project.resolve(inputRel);
  // ProjectFiles.exists is file-only; directories need dart:io (ops already use it).
  if (!Directory(inputAbs).existsSync() &&
      ctx.files.list(inputAbs, recursive: true).isEmpty) {
    throw OpError(ErrorCode.notFound, 'No such input directory "$inputRel".');
  }

  final scales = _parseScales(a['scales']! as String);
  final padding = a['padding']! as int;
  final maxWidth = a['maxWidth']! as int;
  final maxAttempts = a['maxAttempts']! as int;
  final outputImage = a['outputImage']! as String;
  final outputManifest =
      (a['outputManifest'] as String?) ?? defaultManifestPath(outputImage);

  final items = _loadPackItems(ctx, codec, inputAbs);
  if (items.isEmpty) {
    throw OpError(
      ErrorCode.notFound,
      'No images found under "$inputRel".',
      hint: 'Supported extensions: ${_imageExtensions.join(', ')}.',
    );
  }
  final duplicate = _duplicateName(items);
  if (duplicate != null) {
    throw OpError(
      ErrorCode.validationFailed,
      'Two source images both resolve to region name "$duplicate".',
      hint:
          'Region names are basenames without extension; rename one of the colliding files.',
    );
  }

  final changes = <FileChange>[];
  final written = <Map<String, Object?>>[];
  for (var i = 0; i < scales.length; i++) {
    final scale = scales[i];
    ctx.cancellation?.throwIfCancelled();
    ctx.reportProgress(
      progress: i,
      total: scales.length,
      message: 'Packing scale $scale (${i + 1}/${scales.length})',
    );
    final scaled = scale == 1.0
        ? items
        : [
            for (final item in items)
              PackItem(item.name, codec.resize(item.image, scale)),
          ];
    final PackedAtlas packed;
    try {
      packed = packAtlas(
        codec,
        scaled,
        padding: padding,
        maxWidth: maxWidth,
        maxAttempts: maxAttempts,
      );
    } on StateError catch (e) {
      throw OpError(ErrorCode.internal, e.message);
    }
    final imageRel = tieredAtlasPath(outputImage, scale);
    final manifestRel = tieredAtlasPath(outputManifest, scale);
    final png = codec.encodePng(packed.sheet);
    final manifestText = const JsonEncoder.withIndent('  ').convert({
      'regions': {
        for (final e in packed.regions.entries) e.key: e.value.toJson(),
      },
    });

    final imageAbs = project.resolve(imageRel);
    final manifestAbs = project.resolve(manifestRel);
    changes.add(
      FileChange(
        path: imageRel,
        beforeBytes: ctx.files.readBytes(imageAbs),
        afterBytes: Uint8List.fromList(png),
      ),
    );
    changes.add(
      FileChange(
        path: manifestRel,
        before: ctx.files.read(manifestAbs),
        after: manifestText,
      ),
    );
    written.add({
      'image': imageRel,
      'manifest': manifestRel,
      'scale': scale,
      'width': packed.sheet.width,
      'height': packed.sheet.height,
      'regions': packed.regions.length,
    });
  }
  ctx.reportProgress(
    progress: scales.length,
    total: scales.length,
    message: 'Packed ${items.length} images into ${written.length} tier(s)',
  );

  return OpOutcome.proposal(
    Proposal(
      changes,
      summary:
          'Pack ${items.length} images into ${written.length} atlas tier(s).',
    ),
    data: {
      'images': items.length,
      'tiers': written,
      'regions': [for (final i in items) i.name]..sort(),
    },
  );
}

List<double> _parseScales(String text) {
  final scales = <double>[];
  try {
    for (final part in text.split(',')) {
      scales.add(double.parse(part.trim()));
    }
  } on FormatException {
    throw OpError(
      ErrorCode.validationFailed,
      'scales must be a comma-separated list of numbers (got "$text").',
    );
  }
  if (scales.isEmpty || scales.any((s) => s <= 0)) {
    throw OpError(
      ErrorCode.validationFailed,
      'scales values must be > 0 (got "$text").',
    );
  }
  return scales;
}

List<PackItem> _loadPackItems(
  OpContext ctx,
  ImageCodec codec,
  String inputAbs,
) {
  final paths = ctx.files
      .list(inputAbs, recursive: true)
      .where((f) => _imageExtensions.contains(p.extension(f).toLowerCase()))
      .toList()
    ..sort();
  final items = <PackItem>[];
  for (final path in paths) {
    final bytes = ctx.files.readBytes(path);
    if (bytes == null) continue;
    final decoded = codec.decode(bytes);
    if (decoded == null) continue;
    items.add(PackItem(p.basenameWithoutExtension(path), decoded));
  }
  return items;
}

String? _duplicateName(List<PackItem> items) {
  final seen = <String>{};
  for (final item in items) {
    if (!seen.add(item.name)) return item.name;
  }
  return null;
}
