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

    final renderPath = args['render'] as String?;
    if (renderPath == null) return 0;
    return _render(entities, renderPath);
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
