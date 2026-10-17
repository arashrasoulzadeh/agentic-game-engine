import '../command/composite_command.dart';
import '../command/edit_command.dart';
import '../command/prefab_commands.dart';
import '../command/tile_commands.dart';
import 'level_document.dart';
import 'prefab.dart';

/// A reusable stamp for the level editor: a pattern of tiles, or a prefab. Brushes
/// belong to the *project*, not one level, so the same "ledge" or "torch" is at hand in
/// every level.
sealed class Brush {
  String get name;

  Map<String, dynamic> toJson();

  factory Brush.fromJson(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'tiles':
        return TileBrush.fromJson(json);
      case 'prefab':
        return PrefabBrush.fromJson(json);
      default:
        throw FormatException('unknown brush type "${json['type']}"');
    }
  }
}

/// A rectangular pattern of tile ids. [skip] (-1) in the pattern leaves that cell
/// alone, so a brush can be an L-shape or a hollow frame without erasing what is
/// under its gaps; 0 *erases*.
class TileBrush implements Brush {
  static const int skip = -1;

  @override
  final String name;

  /// Rows top to bottom; every row has the same length.
  final List<List<int>> pattern;

  TileBrush({required this.name, required List<List<int>> pattern})
      : pattern = [for (final r in pattern) List.of(r)] {
    if (pattern.isEmpty || pattern.any((r) => r.isEmpty)) {
      throw ArgumentError('a tile brush needs at least one cell');
    }
    if (pattern.any((r) => r.length != pattern.first.length)) {
      throw ArgumentError('every row of a tile brush must be the same length');
    }
  }

  int get width => pattern.first.length;
  int get height => pattern.length;

  /// One undoable step that stamps the pattern with its top-left on ([col], [row]) of
  /// [mapEntity]'s `tileMap`. Cells that fall outside the map are left out (a stamp
  /// near the edge is clipped, not an error). Null if nothing would change.
  EditCommand? stampAt(LevelEntity mapEntity, int col, int row) {
    final map = mapEntity.components['tileMap'];
    if (map == null) return null;
    final cols = (map['cols'] as num).toInt(), rows = (map['rows'] as num).toInt();
    final commands = <EditCommand>[
      for (var r = 0; r < height; r++)
        for (var c = 0; c < width; c++)
          if (pattern[r][c] != skip && col + c >= 0 && col + c < cols && row + r >= 0 && row + r < rows)
            SetTileCommand(entity: mapEntity, col: col + c, row: row + r, tileId: pattern[r][c]),
    ];
    return commands.isEmpty ? null : CompositeCommand('Stamp $name', commands);
  }

  @override
  Map<String, dynamic> toJson() => {'type': 'tiles', 'name': name, 'pattern': pattern};

  factory TileBrush.fromJson(Map<String, dynamic> json) => TileBrush(
        name: json['name'] as String,
        pattern: [
          for (final row in (json['pattern'] as List)) [for (final id in (row as List)) (id as num).toInt()],
        ],
      );
}

/// A brush that places a prefab, referenced by its project path (`prefabs/torch.json`)
/// so editing the prefab updates the brush.
class PrefabBrush implements Brush {
  @override
  final String name;
  final String prefabPath;

  const PrefabBrush({required this.name, required this.prefabPath});

  /// The command that places [prefab] (loaded from [prefabPath] by the caller) at
  /// ([x], [y]).
  EditCommand placeAt(Prefab prefab, double x, double y) => InstantiatePrefabCommand(prefab, x: x, y: y);

  @override
  Map<String, dynamic> toJson() => {'type': 'prefab', 'name': name, 'prefab': prefabPath};

  factory PrefabBrush.fromJson(Map<String, dynamic> json) =>
      PrefabBrush(name: json['name'] as String, prefabPath: json['prefab'] as String);
}

/// The project's brushes, kept in order. Names are unique: adding a brush with an
/// existing name replaces it, so "save brush" twice updates rather than duplicates.
class BrushLibrary {
  final List<Brush> brushes;

  BrushLibrary([List<Brush>? brushes]) : brushes = brushes ?? [];

  Brush? named(String name) {
    for (final b in brushes) {
      if (b.name == name) return b;
    }
    return null;
  }

  void add(Brush brush) {
    final at = brushes.indexWhere((b) => b.name == brush.name);
    if (at >= 0) {
      brushes[at] = brush;
    } else {
      brushes.add(brush);
    }
  }

  bool remove(String name) {
    final before = brushes.length;
    brushes.removeWhere((b) => b.name == name);
    return brushes.length != before;
  }

  Map<String, dynamic> toJson() => {'brushes': [for (final b in brushes) b.toJson()]};

  /// Reads a library, skipping entries that don't parse so one bad brush doesn't hide
  /// the rest.
  factory BrushLibrary.fromJson(Map<String, dynamic> json) {
    final out = <Brush>[];
    for (final raw in (json['brushes'] as List? ?? const [])) {
      try {
        out.add(Brush.fromJson((raw as Map).cast<String, dynamic>()));
      } on Object {
        continue;
      }
    }
    return BrushLibrary(out);
  }
}
