import '../../content/level_document.dart';
import '../../content/level_format.dart';
import '../../physics/tile_map.dart';
import '../../physics/tmx_export.dart';
import '../../physics/tmx_import.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';
import 'level_ops.dart';

/// `level.export_tmx` / `level.import_tmx`: Tiled interchange for a level's tile map.
List<Operation> tmxOperations() => [
  Operation(
    name: 'level.export_tmx',
    summary: 'Write a level\'s tile map as a Tiled .tmx file.',
    description:
        'Only tiles and the four collision sets (solid, one-way, slopes) survive; ladders, conveyors, friction, extra '
        'layers, animations and atlas binding are listed under `lost`. Default output is next to the level.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      Param('path', ParamType.path, required: true, positional: true),
      Param(
        'entity',
        ParamType.string,
        description: 'Entity holding the tileMap; default the first with one.',
      ),
      Param('output', ParamType.path),
      Param('image', ParamType.string, defaultValue: 'tiles.png'),
      Param('tileset', ParamType.string, defaultValue: 'tiles'),
    ],
    handler: (ctx, a) {
      final rel = a['path']! as String;
      final doc = parseLevel(levelText(ctx, a));
      final wanted = a['entity'] as String?;
      LevelEntity? holder;
      for (final e in doc.entities) {
        if (e.components.containsKey('tileMap') &&
            (wanted == null || e.name == wanted)) {
          holder = e;
          break;
        }
      }
      if (holder == null) {
        throw OpError(
          ErrorCode.notFound,
          wanted == null
              ? '$rel has no entity with a tileMap.'
              : 'No entity named "$wanted" with a tileMap in $rel.',
        );
      }
      final TileMap map;
      try {
        map = TileMap.fromJson(holder.components['tileMap']!);
      } on Object catch (e) {
        throw OpError(
          ErrorCode.validationFailed,
          'The tileMap in $rel is not loadable ($e).',
        );
      }
      final out =
          (a['output'] as String?) ??
          rel.replaceFirst(RegExp(r'(\.level)?\.json$'), '.tmx');
      return OpOutcome.proposal(
        Proposal([
          FileChange(
            path: out,
            before: ctx.files.read(ctx.project!.resolve(out)),
            after: tileMapToTmx(
              map,
              tilesetName: a['tileset']! as String,
              imageSource: a['image']! as String,
            ),
          ),
        ]),
        data: {
          'path': out,
          'cols': map.cols,
          'rows': map.rows,
          'lost': [
            if (map.ladderTileIds.isNotEmpty) 'ladders',
            if (map.conveyorSpeedByTileId.isNotEmpty) 'conveyors',
            if (map.frictionByTileId.isNotEmpty) 'friction',
            if (map.backgroundTiles != null || map.foregroundTiles != null)
              'extra layers',
            if (map.tileAnimations.isNotEmpty) 'tile animations',
            if (map.atlasId != null) 'atlas/art binding',
          ],
        },
      );
    },
  ),
  Operation(
    name: 'level.import_tmx',
    summary: 'Create a level from a Tiled .tmx map.',
    description:
        'Makes a new level whose single entity holds the imported tileMap. Fails with `conflict` if the output exists. '
        'Unsupported maps (several layers or tilesets, external tilesets, non-CSV data) are `validation_failed` with the reason.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    params: const [
      Param('tmx', ParamType.path, required: true, positional: true),
      Param(
        'output',
        ParamType.path,
        description: 'Default: assets/levels/<tmx name>.json.',
      ),
      Param('entity', ParamType.string, defaultValue: 'ground'),
    ],
    errors: {ErrorCode.conflict: 'The output level already exists.'},
    handler: (ctx, a) {
      final tmxRel = a['tmx']! as String;
      final xml = ctx.files.read(ctx.project!.resolve(tmxRel));
      if (xml == null) throw OpError(ErrorCode.notFound, 'No file at $tmxRel.');
      final TileMap map;
      try {
        map = tileMapFromTmx(xml);
      } on UnsupportedError catch (e) {
        throw OpError(ErrorCode.validationFailed, '${e.message}');
      } on Object catch (e) {
        throw OpError(
          ErrorCode.validationFailed,
          'Could not read $tmxRel ($e).',
        );
      }
      final base = tmxRel.split('/').last.replaceFirst(RegExp(r'\.tmx$'), '');
      final out = (a['output'] as String?) ?? 'assets/levels/$base.json';
      if (ctx.files.read(ctx.project!.resolve(out)) != null) {
        throw OpError(ErrorCode.conflict, '$out already exists.');
      }
      final doc = LevelDocument(
        entities: [
          LevelEntity(
            name: a['entity']! as String,
            components: {
              'position': {'x': 0.0, 'y': 0.0},
              'tileMap': map.toJson(),
            },
          ),
        ],
      );
      return OpOutcome.proposal(
        Proposal([FileChange(path: out, after: encodeLevelJson(doc.toJson()))]),
        data: {'path': out, 'cols': map.cols, 'rows': map.rows},
      );
    },
  ),
];
