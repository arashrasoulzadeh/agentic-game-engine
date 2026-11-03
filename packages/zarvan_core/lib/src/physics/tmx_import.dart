import 'dart:convert' show base64;

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
/// standard tool for this — using `zarvan lint` or a level editor
/// isn't a requirement to get real level geometry into this engine.
///
/// **What's supported**: one or more `<tileset>`s (Tiled gives each a
/// `firstgid`, so global tile ids stay unique and collision properties merge
/// across them), CSV or base64 `<data>`, one tile layer at a time (see
/// [layer]). Per-tile `bool` custom properties named
/// `"solid"`/`"oneWay"`/`"slopeUpRight"`/`"slopeUpLeft"` (set in Tiled's
/// tileset editor) map onto the matching `TileMap` collision set.
///
/// Two things need the caller, because this Flutter-free, web-targeting package
/// does no file I/O and has no zlib:
/// - an external tileset (`<tileset source="x.tsx">`): pass [readTileset],
///   which receives the `source` string and returns the `.tsx` text (or null
///   when it can't be found, which is reported as an error);
/// - compressed layer data (`compression="zlib"` or `"gzip"`): pass
///   [decompress], which receives the still-compressed bytes and the
///   compression name and returns the raw bytes (`dart:io`'s
///   `ZLibDecoder().convert` / `GZipDecoder().convert` do this on the VM).
///
/// **What's not supported** (throws [UnsupportedError] with a specific
/// message, rather than silently importing something wrong): an external
/// tileset or compressed data without the matching callback, other
/// compressions (e.g. zstd), and XML `<tile>` layer data.
/// Tile flip flags (Tiled's horizontal/vertical/diagonal flip bits on a
/// gid) are silently stripped — the base tile id imports correctly,
/// but a flipped orientation is lost, since `TileMap` has no concept of
/// per-cell tile flipping.
///
/// With several `<layer>`s, pass [layer] (a layer's `name`) to choose the one
/// to import; without it a map that has more than one throws, listing the
/// names.
TileMap tileMapFromTmx(
  String tmxXml, {
  String? layer,
  String? Function(String source)? readTileset,
  List<int> Function(List<int> bytes, String compression)? decompress,
}) {
  final doc = XmlDocument.parse(tmxXml);
  final mapEl = doc.rootElement;
  if (mapEl.name.local != 'map') {
    throw UnsupportedError(
      'Not a Tiled .tmx file: root element is <${mapEl.name.local}>, expected <map>',
    );
  }

  final cols = int.parse(mapEl.getAttribute('width')!);
  final rows = int.parse(mapEl.getAttribute('height')!);
  final tileWidth = double.parse(mapEl.getAttribute('tilewidth')!);
  final tileHeight = double.parse(mapEl.getAttribute('tileheight')!);

  final tilesetEls = mapEl.findElements('tileset').toList();
  if (tilesetEls.isEmpty) {
    throw UnsupportedError('No <tileset> found in this .tmx file');
  }

  final solidTileIds = <int>{};
  final oneWayTileIds = <int>{};
  final slopeUpRightTileIds = <int>{};
  final slopeUpLeftTileIds = <int>{};
  for (final mapTileset in tilesetEls) {
    final firstGid = int.parse(mapTileset.getAttribute('firstgid')!);
    final source = mapTileset.getAttribute('source');
    var tilesetEl = mapTileset;
    if (source != null) {
      final text = readTileset?.call(source);
      if (readTileset == null) {
        throw UnsupportedError(
          'External tileset "$source" needs readTileset: to load it, or re-export with Tiled\'s "Embed Tileset" option',
        );
      }
      if (text == null) {
        throw UnsupportedError('External tileset "$source" could not be read');
      }
      tilesetEl = XmlDocument.parse(text).rootElement;
    }
    for (final tileEl in tilesetEl.findElements('tile')) {
      final globalId = firstGid + int.parse(tileEl.getAttribute('id')!);
      final propertiesEl = tileEl.getElement('properties');
      if (propertiesEl == null) continue;
      for (final propertyEl in propertiesEl.findElements('property')) {
        if (propertyEl.getAttribute('value') != 'true') continue;
        switch (propertyEl.getAttribute('name')) {
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
  }

  final layerEls = mapEl.findElements('layer').toList();
  if (layerEls.isEmpty) {
    throw UnsupportedError('No <layer> found in this .tmx file');
  }
  final names = [
    for (final l in layerEls) l.getAttribute('name') ?? '(unnamed)',
  ];
  final XmlElement layerEl;
  if (layer != null) {
    final matches = [
      for (final l in layerEls)
        if (l.getAttribute('name') == layer) l,
    ];
    if (matches.isEmpty) {
      throw UnsupportedError(
        'No <layer> named "$layer" in this .tmx file. Layers: ${names.join(', ')}',
      );
    }
    layerEl = matches.first;
  } else if (layerEls.length > 1) {
    throw UnsupportedError(
      'Multiple <layer> elements found (${layerEls.length}: ${names.join(', ')}) -- '
      'pass layer: "<name>" to choose the tile layer to import',
    );
  } else {
    layerEl = layerEls.single;
  }
  final dataEl = layerEl.getElement('data');
  if (dataEl == null) {
    throw UnsupportedError('<layer> has no <data> child');
  }
  final encoding = dataEl.getAttribute('encoding');
  final compression = dataEl.getAttribute('compression');
  final List<int> rawGids;
  if (encoding == 'csv') {
    rawGids = dataEl.innerText
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();
  } else if (encoding == 'base64') {
    List<int> bytes = base64.decode(dataEl.innerText.trim());
    if (compression != null) {
      if (decompress == null ||
          (compression != 'zlib' && compression != 'gzip')) {
        throw UnsupportedError(
          'Compressed layer data ("$compression") needs decompress: for zlib/gzip -- or re-export with '
          'Tiled\'s "Tile Layer Format" set to "CSV" or "Base64 (uncompressed)"',
        );
      }
      bytes = decompress(bytes, compression);
    }
    if (bytes.length % 4 != 0) {
      throw UnsupportedError(
        'Base64 layer data is ${bytes.length} bytes, not a multiple of 4 (one little-endian uint32 per tile)',
      );
    }
    rawGids = [
      for (var i = 0; i < bytes.length; i += 4)
        bytes[i] | bytes[i + 1] << 8 | bytes[i + 2] << 16 | bytes[i + 3] << 24,
    ];
  } else {
    throw UnsupportedError(
      'Layer data encoding "${encoding ?? '(tile elements, uncompressed XML)'}" is not supported -- '
      're-export with Tiled\'s "CSV" tile layer format',
    );
  }

  // Tiled reserves the top 3 bits of each gid for flip flags
  // (horizontal 0x80000000, vertical 0x40000000, diagonal 0x20000000);
  // masking them off keeps the base tile id and silently drops
  // orientation, per this function's documented limitation.
  const flipFlagsMask = 0x1FFFFFFF;
  final tiles = [for (final gid in rawGids) gid & flipFlagsMask];

  if (tiles.length != cols * rows) {
    throw UnsupportedError(
      'Layer data has ${tiles.length} tiles, expected ${cols * rows} (map is ${cols}x$rows)',
    );
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
