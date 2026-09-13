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

  factory TileMap.fromJson(Map<String, dynamic> json) => TileMap(
        cols: json['cols'] as int,
        rows: json['rows'] as int,
        tileWidth: (json['tileWidth'] as num).toDouble(),
        tileHeight: (json['tileHeight'] as num).toDouble(),
        tiles: (json['tiles'] as List).cast<int>(),
        solidTileIds: ((json['solidTileIds'] as List?) ?? const []).cast<int>().toSet(),
        oneWayTileIds: ((json['oneWayTileIds'] as List?) ?? const []).cast<int>().toSet(),
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
      );
}
