import 'dart:convert';

import '../operation.dart';
import '../param.dart';
import '../project/asset_index.dart';
import '../result.dart';

/// `asset.*`: what art and data a project contains.
List<Operation> assetOperations() => [
  Operation(
    name: 'asset.index',
    summary:
        'List the project\'s atlases, images, audio, data files and prefabs.',
    description:
        'Atlases come from `assets/studio_atlases.json` (which gives them an id levels can use as `atlasId`) and from any '
        '`X.json` with a `regions` map next to `X.png` (what `game_agent pack-assets` writes). Images already part of an '
        'atlas are not listed again under `images`.',
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
];
