import '../content/level_document.dart';
import '../physics/tile_map.dart';
import 'edit_command.dart';

/// Rewrites a legend-authored `tileMap` (ASCII `rows` plus a `legend`) into the
/// flat `tiles` form that tile edits need. Done once, on the first tile edit.
///
/// The original component JSON is kept, so [revert] restores the legend form
/// exactly. Designers keep their ASCII art until they choose to edit tiles.
class FlattenTileMapCommand implements EditCommand {
  final LevelEntity entity;

  Map<String, dynamic>? _original;

  FlattenTileMapCommand(this.entity);

  @override
  String get label => 'Convert tile map to flat ids';

  @override
  void apply(LevelDocument document) {
    final current = entity.components['tileMap']!;
    _original = current;
    entity.components['tileMap'] = TileMap.fromJson(current).toJson();
  }

  @override
  void revert(LevelDocument document) {
    entity.components['tileMap'] = _original!;
  }
}

/// Sets the tile at ([col], [row]) on [entity]'s `tileMap` to [tileId]. Use tile
/// id 0 to erase. The map must already be in flat form (see
/// [FlattenTileMapCommand]). Revert restores the previous id.
class SetTileCommand implements EditCommand {
  final LevelEntity entity;
  final int col;
  final int row;
  final int tileId;

  int? _previous;

  SetTileCommand({
    required this.entity,
    required this.col,
    required this.row,
    required this.tileId,
  });

  @override
  String get label => tileId == 0 ? 'Erase tile' : 'Paint tile';

  @override
  void apply(LevelDocument document) {
    final map = entity.components['tileMap']!;
    final index = _indexOf(map, col, row);
    final tiles = map['tiles'] as List;
    _previous = tiles[index] as int;
    tiles[index] = tileId;
  }

  @override
  void revert(LevelDocument document) {
    final map = entity.components['tileMap']!;
    (map['tiles'] as List)[_indexOf(map, col, row)] = _previous;
  }
}

/// Replaces the connected region of tiles matching the tile at ([col], [row])
/// with [tileId] (a flood fill, four-connected). The affected cells are chosen
/// at apply time, so [revert] restores each one to the id it had.
class FillRegionCommand implements EditCommand {
  final LevelEntity entity;
  final int col;
  final int row;
  final int tileId;

  final List<(int, int)> _changed = [];
  final List<int> _previousIds = [];

  FillRegionCommand({
    required this.entity,
    required this.col,
    required this.row,
    required this.tileId,
  });

  @override
  String get label => 'Fill region';

  @override
  void apply(LevelDocument document) {
    final map = entity.components['tileMap']!;
    final cols = map['cols'] as int;
    final rows = map['rows'] as int;
    final tiles = map['tiles'] as List;
    final target = tiles[_indexOf(map, col, row)] as int;

    _changed.clear();
    _previousIds.clear();
    if (target == tileId) return;

    final stack = <(int, int)>[(col, row)];
    final seen = <int>{};
    while (stack.isNotEmpty) {
      final (c, r) = stack.removeLast();
      if (c < 0 || c >= cols || r < 0 || r >= rows) continue;
      final index = r * cols + c;
      if (!seen.add(index) || (tiles[index] as int) != target) continue;
      _changed.add((c, r));
      _previousIds.add(tiles[index] as int);
      tiles[index] = tileId;
      stack
        ..add((c + 1, r))
        ..add((c - 1, r))
        ..add((c, r + 1))
        ..add((c, r - 1));
    }
  }

  @override
  void revert(LevelDocument document) {
    final map = entity.components['tileMap']!;
    final tiles = map['tiles'] as List;
    for (var i = 0; i < _changed.length; i++) {
      final (c, r) = _changed[i];
      tiles[_indexOf(map, c, r)] = _previousIds[i];
    }
  }
}

int _indexOf(Map<String, dynamic> map, int col, int row) {
  final cols = map['cols'] as int;
  return row * cols + col;
}
