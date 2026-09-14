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

  /// Ramp tiles a `TileCollisionSystem` walks an entity up/down instead
  /// of blocking it — [slopeUpRightTileIds] rise as `x` increases
  /// within the tile (low on the tile's left edge, high on its right:
  /// walking right goes uphill), [slopeUpLeftTileIds] the mirror
  /// (walking left goes uphill). A tile id in either set is a full
  /// solid rectangle vertically to the shorter side and a straight
  /// diagonal surface across the tile, not true polygon physics — a
  /// walkable surface only, not something that blocks from underneath
  /// or the sides; see `TileCollisionSystem`'s doc comment.
  final Set<int> slopeUpRightTileIds;
  final Set<int> slopeUpLeftTileIds;

  /// Tile ids an entity can climb — not solid on their own (a ladder
  /// tile is typically walkable-through horizontally, not blocking),
  /// purely a marker `TileCollisionSystem` checks for overlap the same
  /// way it checks `solidTileIds`/`oneWayTileIds`. What climbing
  /// *does* (vertical movement, suspending gravity) is genre-specific
  /// logic and lives in `engine_platformer`'s `LadderSystem` — this
  /// set is only the genre-general "which tiles are ladders" data,
  /// same reasoning as every other `*TileIds` set here.
  final Set<int> ladderTileIds;

  /// Horizontal speed (px/s, signed — negative is leftward) added to an
  /// entity resting on this tile id, for conveyor-belt tiles. Empty by
  /// default (no entry for a tile id means "not a conveyor," identical
  /// to today's behavior).
  final Map<int, double> conveyorSpeedByTileId;

  /// Multiplier on how quickly grounded horizontal velocity snaps to
  /// the input target, for tiles with non-default surface friction — a
  /// missing entry (the default for every tile id) means `1.0`,
  /// "instant snap," i.e. today's unchanged behavior. Values below
  /// `1.0` (ice) make the entity slide instead of stopping instantly;
  /// see `PlatformerInputSystem`'s doc comment for exactly how it's
  /// applied.
  final Map<int, double> frictionByTileId;

  /// Which `AtlasRegistry`-registered atlas (see `engine_flutter`'s
  /// `Sprite.atlasId`) `EngineView` draws tile faces from, for tiles
  /// that have an entry in [regionByTileId]. `null` (the default)
  /// means every tile renders as a flat debug-colored rect the way
  /// this engine always has — set this to opt into real textures
  /// instead. Kept as a plain `String` (not a Flutter type) the same
  /// way `Sprite`/`ParallaxLayer` reference their atlas in
  /// `engine_flutter`, so `TileMap` itself stays free of any Flutter
  /// dependency.
  final String? atlasId;

  /// Which named region within [atlasId] to draw for a given tile id —
  /// a tile id with no entry here (the default: empty) still falls
  /// back to the flat debug color, even when [atlasId] is set, so a
  /// level can texture some tile ids (visible terrain) while leaving
  /// others (an invisible trigger/hazard marker id, say) as before.
  final Map<int, String> regionByTileId;

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
    Set<int>? slopeUpRightTileIds,
    Set<int>? slopeUpLeftTileIds,
    Set<int>? ladderTileIds,
    Map<int, double>? conveyorSpeedByTileId,
    Map<int, double>? frictionByTileId,
    this.atlasId,
    Map<int, String>? regionByTileId,
    this.zIndex = 0,
  })  : solidTileIds = solidTileIds ?? <int>{},
        oneWayTileIds = oneWayTileIds ?? <int>{},
        slopeUpRightTileIds = slopeUpRightTileIds ?? <int>{},
        slopeUpLeftTileIds = slopeUpLeftTileIds ?? <int>{},
        ladderTileIds = ladderTileIds ?? <int>{},
        conveyorSpeedByTileId = conveyorSpeedByTileId ?? <int, double>{},
        frictionByTileId = frictionByTileId ?? <int, double>{},
        regionByTileId = regionByTileId ?? <int, String>{} {
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
  bool isSlopeUpRight(int col, int row) => slopeUpRightTileIds.contains(tileAt(col, row));
  bool isSlopeUpLeft(int col, int row) => slopeUpLeftTileIds.contains(tileAt(col, row));
  bool isLadder(int col, int row) => ladderTileIds.contains(tileAt(col, row));

  Map<String, dynamic> toJson() => {
        'cols': cols,
        'rows': rows,
        'tileWidth': tileWidth,
        'tileHeight': tileHeight,
        'tiles': tiles,
        'solidTileIds': solidTileIds.toList(),
        'oneWayTileIds': oneWayTileIds.toList(),
        'slopeUpRightTileIds': slopeUpRightTileIds.toList(),
        'slopeUpLeftTileIds': slopeUpLeftTileIds.toList(),
        'ladderTileIds': ladderTileIds.toList(),
        'conveyorSpeedByTileId': conveyorSpeedByTileId.map((k, v) => MapEntry(k.toString(), v)),
        'frictionByTileId': frictionByTileId.map((k, v) => MapEntry(k.toString(), v)),
        if (atlasId != null) 'atlasId': atlasId,
        'regionByTileId': regionByTileId.map((k, v) => MapEntry(k.toString(), v)),
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
    final slopeUpRightTileIds =
        ((json['slopeUpRightTileIds'] as List?) ?? const []).cast<int>().toSet();
    final slopeUpLeftTileIds =
        ((json['slopeUpLeftTileIds'] as List?) ?? const []).cast<int>().toSet();
    final ladderTileIds = ((json['ladderTileIds'] as List?) ?? const []).cast<int>().toSet();
    final conveyorSpeedByTileId = ((json['conveyorSpeedByTileId'] as Map?) ?? const {})
        .map((k, v) => MapEntry(int.parse(k as String), (v as num).toDouble()));
    final frictionByTileId = ((json['frictionByTileId'] as Map?) ?? const {})
        .map((k, v) => MapEntry(int.parse(k as String), (v as num).toDouble()));
    final atlasId = json['atlasId'] as String?;
    final regionByTileId = ((json['regionByTileId'] as Map?) ?? const {})
        .map((k, v) => MapEntry(int.parse(k as String), v as String));
    if (legend != null) {
      return _fromLegend(
        legend: (legend as Map).cast<String, dynamic>(),
        asciiRows: (json['rows'] as List).cast<String>(),
        tileWidth: (json['tileWidth'] as num).toDouble(),
        tileHeight: (json['tileHeight'] as num).toDouble(),
        solidTileIds: solidTileIds,
        oneWayTileIds: oneWayTileIds,
        slopeUpRightTileIds: slopeUpRightTileIds,
        slopeUpLeftTileIds: slopeUpLeftTileIds,
        ladderTileIds: ladderTileIds,
        conveyorSpeedByTileId: conveyorSpeedByTileId,
        frictionByTileId: frictionByTileId,
        atlasId: atlasId,
        regionByTileId: regionByTileId,
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
      slopeUpRightTileIds: slopeUpRightTileIds,
      slopeUpLeftTileIds: slopeUpLeftTileIds,
      ladderTileIds: ladderTileIds,
      conveyorSpeedByTileId: conveyorSpeedByTileId,
      frictionByTileId: frictionByTileId,
      atlasId: atlasId,
      regionByTileId: regionByTileId,
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
    required Set<int> slopeUpRightTileIds,
    required Set<int> slopeUpLeftTileIds,
    required Set<int> ladderTileIds,
    required Map<int, double> conveyorSpeedByTileId,
    required Map<int, double> frictionByTileId,
    required String? atlasId,
    required Map<int, String> regionByTileId,
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
      slopeUpRightTileIds: slopeUpRightTileIds,
      slopeUpLeftTileIds: slopeUpLeftTileIds,
      ladderTileIds: ladderTileIds,
      conveyorSpeedByTileId: conveyorSpeedByTileId,
      frictionByTileId: frictionByTileId,
      atlasId: atlasId,
      regionByTileId: regionByTileId,
      zIndex: zIndex,
    );
  }
}
