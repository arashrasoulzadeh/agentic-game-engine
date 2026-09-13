/// A grid of tile ids (0 = empty) plus which ids are solid/one-way for
/// collision — distinct from per-entity `PlatformBody` rectangles, since
/// most 2D levels are authored as a tile grid rather than one entity
/// per platform. Attach to an entity that also has a `Position`
/// (the grid's world-space origin, i.e. its top-left corner);
/// `TileCollisionSystem` reads both.
class TileMap {
  final int cols;
  final int rows;
  final double tileWidth;
  final double tileHeight;
  final List<int> tiles;
  final Set<int> solidTileIds;
  final Set<int> oneWayTileIds;

  /// Draw order relative to every other renderable (`Sprite`,
  /// `ParallaxLayer`, another `TileMap`, `Particle`) — see
  /// `engine_flutter`'s `Sprite.zIndex` for the full rule. Useful for a
  /// second, foreground `TileMap` (decorative overhang tiles, a mask
  /// layer) drawn above characters instead of below them; collision
  /// still comes from `solidTileIds`/`oneWayTileIds` regardless of
  /// `zIndex`, which only affects rendering.
  final int zIndex;

  TileMap({
    required this.cols,
    required this.rows,
    required this.tileWidth,
    required this.tileHeight,
    required this.tiles,
    Set<int>? solidTileIds,
    Set<int>? oneWayTileIds,
    this.zIndex = 0,
  })  : solidTileIds = solidTileIds ?? <int>{},
        oneWayTileIds = oneWayTileIds ?? <int>{} {
    if (tiles.length != cols * rows) {
      throw ArgumentError(
          'tiles.length (${tiles.length}) must equal cols*rows (${cols * rows})');
    }
  }

  int tileAt(int col, int row) {
    if (col < 0 || col >= cols || row < 0 || row >= rows) return 0;
    return tiles[row * cols + col];
  }

  bool isSolid(int col, int row) => solidTileIds.contains(tileAt(col, row));
  bool isOneWay(int col, int row) => oneWayTileIds.contains(tileAt(col, row));

  Map<String, dynamic> toJson() => {
        'cols': cols,
        'rows': rows,
        'tileWidth': tileWidth,
        'tileHeight': tileHeight,
        'tiles': tiles,
        'solidTileIds': solidTileIds.toList(),
        'oneWayTileIds': oneWayTileIds.toList(),
        'zIndex': zIndex,
      };

  /// Accepts either the raw `cols`/`rows`/`tiles` (flat id array) shape
  /// `toJson` emits, or a human-authorable alternative: `legend` (a
  /// character -> tile id map) plus `rows` as a `List<String>`, one row
  /// per string, one character per column. The legend form is what a
  /// human or agent should actually author by hand — a several-hundred
  /// entry flat int array reads as noise, while a handful of ASCII rows
  /// reads as the level's shape at a glance. Both forms produce an
  /// identical `TileMap`; `toJson` always emits the flat-array form, so
  /// a legend-authored level re-serializes (e.g. via `SaveGame`) as
  /// plain ids — round-tripping the ASCII art itself isn't required.
  factory TileMap.fromJson(Map<String, dynamic> json) {
    final legend = json['legend'];
    final zIndex = (json['zIndex'] as num?)?.toInt() ?? 0;
    final solidTileIds = ((json['solidTileIds'] as List?) ?? const []).cast<int>().toSet();
    final oneWayTileIds = ((json['oneWayTileIds'] as List?) ?? const []).cast<int>().toSet();
    if (legend != null) {
      return _fromLegend(
        legend: (legend as Map).cast<String, dynamic>(),
        asciiRows: (json['rows'] as List).cast<String>(),
        tileWidth: (json['tileWidth'] as num).toDouble(),
        tileHeight: (json['tileHeight'] as num).toDouble(),
        solidTileIds: solidTileIds,
        oneWayTileIds: oneWayTileIds,
        zIndex: zIndex,
      );
    }
    return TileMap(
      cols: json['cols'] as int,
      rows: json['rows'] as int,
      tileWidth: (json['tileWidth'] as num).toDouble(),
      tileHeight: (json['tileHeight'] as num).toDouble(),
      tiles: (json['tiles'] as List).cast<int>(),
      solidTileIds: solidTileIds,
      oneWayTileIds: oneWayTileIds,
      zIndex: zIndex,
    );
  }

  static TileMap _fromLegend({
    required Map<String, dynamic> legend,
    required List<String> asciiRows,
    required double tileWidth,
    required double tileHeight,
    required Set<int> solidTileIds,
    required Set<int> oneWayTileIds,
    required int zIndex,
  }) {
    if (asciiRows.isEmpty) {
      throw ArgumentError('TileMap "rows" must not be empty when using "legend"');
    }
    final cols = asciiRows.first.length;
    final tiles = <int>[];
    for (var r = 0; r < asciiRows.length; r++) {
      final row = asciiRows[r];
      if (row.length != cols) {
        throw ArgumentError(
            'TileMap "rows"[$r] has length ${row.length}, expected $cols (row 0\'s length) — every row must be the same width');
      }
      for (final ch in row.split('')) {
        final id = legend[ch];
        if (id == null) {
          throw ArgumentError('TileMap "legend" has no entry for character "$ch"');
        }
        tiles.add(id as int);
      }
    }
    return TileMap(
      cols: cols,
      rows: asciiRows.length,
      tileWidth: tileWidth,
      tileHeight: tileHeight,
      tiles: tiles,
      solidTileIds: solidTileIds,
      oneWayTileIds: oneWayTileIds,
      zIndex: zIndex,
    );
  }
}
