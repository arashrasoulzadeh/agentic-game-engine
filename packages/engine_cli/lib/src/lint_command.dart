import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core.dart';
import 'package:image/image.dart' as img;

/// Pixels per tile in a `--render` PNG — not the level's own
/// `tileWidth`/`tileHeight` (which could be tiny or huge), so a level
/// with 8px tiles and one with 128px tiles render at a consistent,
/// readable size either way.
const _pixelsPerTile = 16;

/// Tile-collision-kind colors — chosen to be distinguishable from each
/// other and from the black entity-marker dots at a glance, not to
/// match any particular game's actual art (this is a structural
/// preview, not a mockup of what the level will look like rendered).
final _emptyColor = img.ColorRgb8(30, 30, 34);
final _solidColor = img.ColorRgb8(120, 120, 128);
final _oneWayColor = img.ColorRgb8(140, 180, 220);
final _slopeColor = img.ColorRgb8(210, 150, 90);
final _entityMarkerColor = img.ColorRgb8(230, 60, 60);

class LintCommand extends Command<int> {
  @override
  final name = 'lint';
  @override
  final description = 'Validate a level/content JSON file without running the game.';

  LintCommand() {
    argParser.addOption(
      'render',
      help: 'Also rasterize the level\'s TileMap (plus a marker per '
          'entity with a position) to a PNG at this path, so a human or '
          'agent can see the level\'s shape without running the game. '
          'Errors if the level has no tileMap component.',
    );
    argParser.addFlag(
      'playable',
      help: 'Also check that every positioned entity is reachable from the '
          'spawn point (an entity whose name contains "player" or "spawn", '
          'case-insensitive) by flood-filling the TileMap\'s non-solid '
          'tiles. Catches an entity sealed off by solid tiles, but not a '
          'gap too wide to jump -- this is tile-connectivity, not physics. '
          'Errors if the level has no tileMap component or no spawn entity.',
    );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    if (args.rest.isEmpty) {
      usageException('Missing file path, e.g. `game_agent lint assets/level1.json`');
    }

    final file = File(args.rest.first);
    if (!file.existsSync()) {
      stderr.writeln('Error: ${file.path} does not exist.');
      return 1;
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } on FormatException catch (e) {
      stderr.writeln('Error: ${file.path} is not valid JSON: ${e.message}');
      return 1;
    }

    final List<Map<String, dynamic>> entities;
    try {
      entities = Level.validate(json);
    } on LevelLoadException catch (e) {
      stderr.writeln('${file.path}: ${e.message}');
      return 1;
    }
    stdout.writeln('${file.path}: OK (${entities.length} entities)');

    var exitCode = 0;

    if (args['playable'] as bool) {
      final playableResult = _checkPlayable(entities);
      if (playableResult != 0) exitCode = playableResult;
    }

    final renderPath = args['render'] as String?;
    if (renderPath != null) {
      final renderResult = _render(entities, renderPath);
      if (renderResult != 0) exitCode = renderResult;
    }

    return exitCode;
  }

  /// Flood-fills the level's non-solid tiles starting from the spawn
  /// entity (name contains "player" or "spawn", case-insensitive) and
  /// reports any other positioned entity whose tile isn't reached --
  /// e.g. an item or exit accidentally sealed behind solid tiles.
  ///
  /// This is tile connectivity, not physics: it doesn't know a
  /// platformer's jump height/gap width, so it can pass a level with a
  /// gap too wide to actually jump across. It exists to catch the more
  /// common authoring mistake (a wall or missing doorway that seals a
  /// region off entirely), not to replace playtesting.
  int _checkPlayable(List<Map<String, dynamic>> entities) {
    Map<String, dynamic>? tileMapJson;
    final positioned = <(String name, double x, double y)>[];
    for (final entity in entities) {
      final components = entity['components'] as Map<String, dynamic>? ?? const {};
      final position = components['position'] as Map<String, dynamic>?;
      final tileMap = components['tileMap'] as Map<String, dynamic>?;
      if (tileMap != null) tileMapJson = tileMap;
      if (position != null) {
        positioned.add((
          entity['name'] as String? ?? '<unnamed>',
          (position['x'] as num).toDouble(),
          (position['y'] as num).toDouble(),
        ));
      }
    }

    if (tileMapJson == null) {
      stderr.writeln('Error: --playable requires a "tileMap" component somewhere in this level; none found.');
      return 1;
    }
    final map = TileMap.fromJson(tileMapJson);

    final spawnIndex = positioned.indexWhere(
      (e) => e.$1.toLowerCase().contains('player') || e.$1.toLowerCase().contains('spawn'),
    );
    if (spawnIndex == -1) {
      stderr.writeln(
        'Error: --playable found no spawn entity (a positioned entity named '
        'with "player" or "spawn" in it).',
      );
      return 1;
    }
    final spawn = positioned[spawnIndex];

    int colOf(double x) => (x / map.tileWidth).floor();
    int rowOf(double y) => (y / map.tileHeight).floor();
    bool solid(int col, int row) {
      if (col < 0 || col >= map.cols || row < 0 || row >= map.rows) return true;
      return map.solidTileIds.contains(map.tileAt(col, row));
    }

    final startCol = colOf(spawn.$2);
    final startRow = rowOf(spawn.$3);
    final reachable = <int>{};
    if (!solid(startCol, startRow)) {
      final queue = [(startCol, startRow)];
      reachable.add(startRow * map.cols + startCol);
      const dirs = [(-1, 0), (1, 0), (0, -1), (0, 1)];
      while (queue.isNotEmpty) {
        final (col, row) = queue.removeLast();
        for (final (dc, dr) in dirs) {
          final nCol = col + dc;
          final nRow = row + dr;
          if (solid(nCol, nRow)) continue;
          final key = nRow * map.cols + nCol;
          if (!reachable.add(key)) continue;
          queue.add((nCol, nRow));
        }
      }
    }

    final unreachable = <String>[];
    for (var i = 0; i < positioned.length; i++) {
      if (i == spawnIndex) continue;
      final (name, x, y) = positioned[i];
      final key = rowOf(y) * map.cols + colOf(x);
      if (!reachable.contains(key)) unreachable.add(name);
    }

    if (solid(startCol, startRow)) {
      stderr.writeln('Error: --playable spawn entity "${spawn.$1}" sits on a solid tile.');
      return 1;
    }
    if (unreachable.isNotEmpty) {
      stderr.writeln(
        '--playable: ${unreachable.length} entity(ies) unreachable from spawn '
        '"${spawn.$1}": ${unreachable.join(', ')}',
      );
      return 1;
    }
    stdout.writeln('--playable: OK (all ${positioned.length - 1} other entities reachable from "${spawn.$1}")');
    return 0;
  }

  int _render(List<Map<String, dynamic>> entities, String outputPath) {
    Map<String, dynamic>? tileMapJson;
    final positions = <(double x, double y, String? name)>[];
    for (final entity in entities) {
      final components = entity['components'] as Map<String, dynamic>? ?? const {};
      final position = components['position'] as Map<String, dynamic>?;
      final tileMap = components['tileMap'] as Map<String, dynamic>?;
      if (tileMap != null) {
        tileMapJson = tileMap;
      } else if (position != null) {
        positions.add((
          (position['x'] as num).toDouble(),
          (position['y'] as num).toDouble(),
          entity['name'] as String?,
        ));
      }
    }

    if (tileMapJson == null) {
      stderr.writeln('Error: --render requires a "tileMap" component somewhere in this level; none found.');
      return 1;
    }

    final map = TileMap.fromJson(tileMapJson);
    final image = img.Image(width: map.cols * _pixelsPerTile, height: map.rows * _pixelsPerTile);
    img.fill(image, color: _emptyColor);

    for (var row = 0; row < map.rows; row++) {
      for (var col = 0; col < map.cols; col++) {
        final tileId = map.tileAt(col, row);
        if (tileId == 0) continue;
        final color = map.isSolid(col, row)
            ? _solidColor
            : map.isOneWay(col, row)
                ? _oneWayColor
                : (map.isSlopeUpRight(col, row) || map.isSlopeUpLeft(col, row))
                    ? _slopeColor
                    : _emptyColor; // a tile id with no recognized collision kind
        img.fillRect(
          image,
          x1: col * _pixelsPerTile,
          y1: row * _pixelsPerTile,
          x2: (col + 1) * _pixelsPerTile - 1,
          y2: (row + 1) * _pixelsPerTile - 1,
          color: color,
        );
      }
    }

    // Entity markers use the level's own world-space coordinates scaled
    // into this render's pixel grid, via the TileMap's own tile size --
    // consistent regardless of _pixelsPerTile.
    final scaleX = _pixelsPerTile / map.tileWidth;
    final scaleY = _pixelsPerTile / map.tileHeight;
    for (final (x, y, name) in positions) {
      final px = (x * scaleX).round();
      final py = (y * scaleY).round();
      img.fillCircle(image, x: px, y: py, radius: 3, color: _entityMarkerColor);
      if (name != null) {
        img.drawString(image, name, font: img.arial14, x: px + 5, y: py - 6, color: _entityMarkerColor);
      }
    }

    File(outputPath).writeAsBytesSync(img.encodePng(image));
    stdout.writeln('$outputPath: rendered (${map.cols}x${map.rows} tiles, ${positions.length} entity markers)');
    return 0;
  }
}
