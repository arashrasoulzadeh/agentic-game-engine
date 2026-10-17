import 'package:xml/xml.dart';

import 'tile_map.dart';

/// Writes [map] as a Tiled `.tmx` file: one embedded tileset, one CSV tile layer. The
/// inverse of `tileMapFromTmx`, so a level built in the studio can be opened in Tiled
/// and brought back.
///
/// Tile ids are written as Tiled global ids with `firstgid="1"` (0 is Tiled's empty
/// cell, the same convention the importer reads back), and the tile properties
/// `solid`, `oneWay`, `slopeUpRight`, `slopeUpLeft` are written for the matching
/// collision sets - exactly the four the importer understands.
///
/// **Not represented** (Tiled has no field the importer reads for them): ladders,
/// conveyor speeds, friction, collision groups, background/foreground layers, tile
/// animations, the atlas id and region names. A level that uses them round-trips its
/// tiles and the four collision sets, and loses the rest when re-imported.
///
/// Tiled wants a tileset image: [imageSource] (relative to the .tmx) with its pixel
/// size. Only the path matters to a round trip; give the real sheet to see the art in
/// Tiled.
String tileMapToTmx(
  TileMap map, {
  String tilesetName = 'tiles',
  String imageSource = 'tiles.png',
  int? imageWidth,
  int? imageHeight,
  int? columns,
}) {
  final highest = map.tiles.fold<int>(0, (m, t) => t > m ? t : m);
  final propertyIds = <int>{
    ...map.solidTileIds,
    ...map.oneWayTileIds,
    ...map.slopeUpRightTileIds,
    ...map.slopeUpLeftTileIds,
  };
  final count = [highest, ...propertyIds].fold<int>(1, (m, t) => t > m ? t : m);
  final cols = columns ?? count;
  final width = imageWidth ?? (map.tileWidth * cols).round();
  final height = imageHeight ?? (map.tileHeight * ((count + cols - 1) ~/ cols)).round();

  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element('map', attributes: {
    'version': '1.10',
    'orientation': 'orthogonal',
    'renderorder': 'right-down',
    'width': '${map.cols}',
    'height': '${map.rows}',
    'tilewidth': _num(map.tileWidth),
    'tileheight': _num(map.tileHeight),
  }, nest: () {
    builder.element('tileset', attributes: {
      'firstgid': '1',
      'name': tilesetName,
      'tilewidth': _num(map.tileWidth),
      'tileheight': _num(map.tileHeight),
      'tilecount': '$count',
      'columns': '$cols',
    }, nest: () {
      builder.element('image', attributes: {'source': imageSource, 'width': '$width', 'height': '$height'});
      for (final id in propertyIds.toList()..sort()) {
        // A property id below 1 would be a local id of -1; the importer cannot
        // express "tile 0" (empty), so such an id carries nothing and is skipped.
        if (id < 1) continue;
        builder.element('tile', attributes: {'id': '${id - 1}'}, nest: () {
          builder.element('properties', nest: () {
            void flag(String name, Set<int> ids) {
              if (ids.contains(id)) {
                builder.element('property', attributes: {'name': name, 'type': 'bool', 'value': 'true'});
              }
            }

            flag('solid', map.solidTileIds);
            flag('oneWay', map.oneWayTileIds);
            flag('slopeUpRight', map.slopeUpRightTileIds);
            flag('slopeUpLeft', map.slopeUpLeftTileIds);
          });
        });
      }
    });
    builder.element('layer', attributes: {
      'id': '1',
      'name': 'Tile Layer 1',
      'width': '${map.cols}',
      'height': '${map.rows}',
    }, nest: () {
      builder.element('data', attributes: {'encoding': 'csv'}, nest: () {
        final rows = <String>[];
        for (var r = 0; r < map.rows; r++) {
          rows.add(map.tiles.sublist(r * map.cols, (r + 1) * map.cols).join(','));
        }
        // Tiled writes a trailing comma on every row but the last.
        builder.text('\n${rows.join(',\n')}\n');
      });
    });
  });
  return builder.buildDocument().toXmlString(pretty: true, indent: ' ');
}

/// `16.0` -> `16`, `16.5` -> `16.5`: Tiled writes whole tile sizes without a decimal.
String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
