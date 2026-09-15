import 'tile_map.dart';

/// Computes the 4-bit orthogonal-neighbor bitmask (0-15) for the cell at
/// [col]/[row] in [map]: bit `1` (north) set when the tile directly above
/// is in [wallTileIds], bit `2` (east), bit `4` (south), bit `8` (west) —
/// the standard 4-direction autotile bitmask, so an edge/corner variant
/// can be picked purely from which orthogonal neighbors are also "wall."
/// A neighbor off the grid edge counts as "not a wall" ([TileMap.tileAt]
/// already returns `0` out of bounds, and `0` is never a meaningful wall
/// id) — deliberately not a wraparound or an assumed-solid edge, since
/// either would silently change a level author's intent for boundary
/// tiles without them asking for it.
int autotileBitmask(TileMap map, int col, int row, Set<int> wallTileIds) {
  var mask = 0;
  if (wallTileIds.contains(map.tileAt(col, row - 1))) mask |= 1;
  if (wallTileIds.contains(map.tileAt(col + 1, row))) mask |= 2;
  if (wallTileIds.contains(map.tileAt(col, row + 1))) mask |= 4;
  if (wallTileIds.contains(map.tileAt(col - 1, row))) mask |= 8;
  return mask;
}

/// The region-name convention every autotile-resolved variant uses:
/// [baseName] followed by its [bitmask], e.g.
/// `autotileRegionName('wall', 13) == 'wall_13'` — a level's atlas
/// manifest is expected to define one region per bitmask value (0-15)
/// under this naming scheme for each autotiled base tile.
String autotileRegionName(String baseName, int bitmask) => '${baseName}_$bitmask';

/// The synthetic tile id [withAutotile] substitutes for [baseTileId] at
/// a cell whose neighbor [bitmask] was computed by [autotileBitmask].
/// Reserves ids at `1000000 + baseTileId*16 + bitmask` and up — comfortably
/// above any id a hand-authored or generated level in this engine
/// actually uses — so every one of a base tile's 16 possible variants
/// gets its own distinct, deterministic id without colliding with real
/// content ids or with another base tile's own variants.
int autotileSyntheticId(int baseTileId, int bitmask) => 1000000 + baseTileId * 16 + bitmask;
