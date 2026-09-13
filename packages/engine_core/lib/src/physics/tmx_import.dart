import 'package:xml/xml.dart';

import 'tile_map.dart';

/// Property names this importer recognizes on a Tiled tile and maps
/// onto `TileMap`'s collision sets — a bool custom property with one of
/// these names, set to `true` on a tile in the tileset editor, is all
/// that's needed; nothing else about a level's Tiled authoring changes.
const _solidProperty = 'solid';
const _oneWayProperty = 'oneWay';
const _slopeUpRightProperty = 'slopeUpRight';
const _slopeUpLeftProperty = 'slopeUpLeft';

/// Imports a Tiled (mapeditor.org) `.tmx` map — exported with an
/// **embedded** tileset (Tiled's "Embed Tileset" option, so the whole
/// map is one self-contained XML file) and its tile layer's data saved
/// as **CSV** (Tiled's default layer export format) — into a `TileMap`.
///
/// This exists so a level doesn't have to be hand-authored as JSON (or
/// generated) when a real tileset/level was already built in Tiled, the
/// standard tool for this — using `game_agent lint` or a level editor
/// isn't a requirement to get real level geometry into this engine.
///
/// **What's supported**: one embedded `<tileset>` (no `source=` — an
/// external `.tsx` file reference is out of scope, since resolving it
/// would need file I/O this Flutter-free, web-targeting package
/// deliberately doesn't do), one `<layer>`, CSV-encoded `<data>`.
/// Per-tile `bool` custom properties named `"solid"`/`"oneWay"`/
/// `"slopeUpRight"`/`"slopeUpLeft"` (set in Tiled's tileset editor) map
/// onto the matching `TileMap` collision set.
///
/// **What's not supported** (throws [UnsupportedError] with a specific
/// message, rather than silently importing something wrong): more than
/// one tileset or layer, an external tileset (`source=`), non-CSV
/// layer encoding (base64, with or without zlib/gzip compression).
/// Tile flip flags (Tiled's horizontal/vertical/diagonal flip bits on a
/// gid) are silently stripped — the base tile id imports correctly,
/// but a flipped orientation is lost, since `TileMap` has no concept of
/// per-cell tile flipping.
TileMap tileMapFromTmx(String tmxXml) {
  final doc = XmlDocument.parse(tmxXml);
  final mapEl = doc.rootElement;
  if (mapEl.name.local != 'map') {
    throw UnsupportedError('Not a Tiled .tmx file: root element is <${mapEl.name.local}>, expected <map>');
  }

  final cols = int.parse(mapEl.getAttribute('width')!);
  final rows = int.parse(mapEl.getAttribute('height')!);
  final tileWidth = double.parse(mapEl.getAttribute('tilewidth')!);
  final tileHeight = double.parse(mapEl.getAttribute('tileheight')!);

  final tilesetEls = mapEl.findElements('tileset').toList();
  if (tilesetEls.isEmpty) {
    throw UnsupportedError('No <tileset> found in this .tmx file');
  }
  if (tilesetEls.length > 1) {
    throw UnsupportedError(
        'Multiple <tileset> elements found (${tilesetEls.length}) -- tileMapFromTmx only supports a single embedded tileset');
  }
  final tilesetEl = tilesetEls.single;
  if (tilesetEl.getAttribute('source') != null) {
    throw UnsupportedError(
        'External tileset file ("source" attribute) is not supported -- re-export with Tiled\'s "Embed Tileset" option');
  }
  final firstGid = int.parse(tilesetEl.getAttribute('firstgid')!);

  final solidTileIds = <int>{};
  final oneWayTileIds = <int>{};
  final slopeUpRightTileIds = <int>{};
  final slopeUpLeftTileIds = <int>{};
  for (final tileEl in tilesetEl.findElements('tile')) {
    final localId = int.parse(tileEl.getAttribute('id')!);
    final globalId = firstGid + localId;
    final propertiesEl = tileEl.getElement('properties');
    if (propertiesEl == null) continue;
    for (final propertyEl in propertiesEl.findElements('property')) {
      final name = propertyEl.getAttribute('name');
      final value = propertyEl.getAttribute('value');
      if (value != 'true') continue;
      switch (name) {
        case _solidProperty:
          solidTileIds.add(globalId);
        case _oneWayProperty:
          oneWayTileIds.add(globalId);
        case _slopeUpRightProperty:
          slopeUpRightTileIds.add(globalId);
        case _slopeUpLeftProperty:
          slopeUpLeftTileIds.add(globalId);
      }
    }
  }

  final layerEls = mapEl.findElements('layer').toList();
  if (layerEls.isEmpty) {
    throw UnsupportedError('No <layer> found in this .tmx file');
  }
  if (layerEls.length > 1) {
    throw UnsupportedError(
        'Multiple <layer> elements found (${layerEls.length}) -- tileMapFromTmx only supports a single tile layer');
  }
  final dataEl = layerEls.single.getElement('data');
  if (dataEl == null) {
    throw UnsupportedError('<layer> has no <data> child');
  }
  final encoding = dataEl.getAttribute('encoding');
  if (encoding != 'csv') {
    throw UnsupportedError(
        'Layer data encoding "${encoding ?? '(tile elements, uncompressed XML)'}" is not supported -- '
        're-export with Tiled\'s "CSV" tile layer format');
  }

  // Tiled reserves the top 3 bits of each gid for flip flags
  // (horizontal 0x80000000, vertical 0x40000000, diagonal 0x20000000);
  // masking them off keeps the base tile id and silently drops
  // orientation, per this function's documented limitation.
  const flipFlagsMask = 0x1FFFFFFF;
  final tiles = dataEl.innerText
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .map((s) => int.parse(s) & flipFlagsMask)
      .toList();

  if (tiles.length != cols * rows) {
    throw UnsupportedError(
        'Layer data has ${tiles.length} tiles, expected ${cols * rows} (map is ${cols}x$rows)');
  }

  return TileMap(
    cols: cols,
    rows: rows,
    tileWidth: tileWidth,
    tileHeight: tileHeight,
    tiles: tiles,
    solidTileIds: solidTileIds,
    oneWayTileIds: oneWayTileIds,
    slopeUpRightTileIds: slopeUpRightTileIds,
    slopeUpLeftTileIds: slopeUpLeftTileIds,
  );
}
