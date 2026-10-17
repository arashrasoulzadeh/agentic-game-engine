import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// Which of the three looks a cell has for the local team.
enum FogCellState { unknown, explored, visible }

/// One shading tile of the fog overlay. A component (not a private list) so the
/// overlay is world state like everything else and the system can find and reuse
/// its own tiles.
class FogShadeCell {
  final int col;
  final int row;
  FogCellState state;
  FogShadeCell(this.col, this.row, this.state);

  Map<String, dynamic> toJson() => {'col': col, 'row': row, 'state': state.name};
  factory FogShadeCell.fromJson(Map<String, dynamic> json) => FogShadeCell(
        (json['col'] as num).toInt(),
        (json['row'] as num).toInt(),
        FogCellState.values.firstWhere((s) => s.name == json['state'], orElse: () => FogCellState.unknown),
      );
}

/// Holds an enemy unit's `Sprite` while it stands where the local team cannot see
/// it. `Sprite` has no visibility flag, so "hidden" means the sprite is moved
/// here and restored when the unit is seen again. A component so a save taken
/// mid-fog does not lose enemy sprites.
class FogHidden {
  final Sprite sprite;
  FogHidden(this.sprite);

  Map<String, dynamic> toJson() => {'sprite': sprite.toJson()};
  factory FogHidden.fromJson(Map<String, dynamic> json) =>
      FogHidden(Sprite.fromJson((json['sprite'] as Map).cast<String, dynamic>()));
}

/// Draws the fog of war for one team: a shade over every cell it has not seen
/// (opaque) or only remembers (translucent), and hides enemy sprites standing in
/// cells it cannot currently see.
///
/// Reads `FogOfWar` (kept current by `VisionSystem`, which must run earlier) and
/// only touches a tile when its state actually changes.
class FogShadeSystem extends System {
  FogShadeSystem({
    required this.team,
    required this.cellSize,
    required this.atlasId,
    required this.unknownRegion,
    required this.exploredRegion,
    required this.clearRegion,
    this.hideEnemies = true,
    this.zIndex = 100,
    this.spriteSize = 32,
  });

  /// The team whose view is shown (the local player).
  final String team;
  final double cellSize;
  final String atlasId;
  final String unknownRegion;
  final String exploredRegion;

  /// A fully transparent region, shown over visible cells. A region rather than
  /// removing the sprite so a tile never has to be recreated when sight changes.
  final String clearRegion;
  final bool hideEnemies;
  final int zIndex;
  final double spriteSize;

  @override
  String get name => 'fogShade';

  @override
  void update(World world, double dt) {
    final fog = fogOf(world);
    if (fog == null) return;
    final cells = world.storeOf<FogShadeCell>();
    if (cells.length != fog.cols * fog.rows) {
      for (var i = cells.length - 1; i >= 0; i--) {
        world.destroy(cells.entityAt(i));
      }
      _spawnTiles(world, fog);
    }
    for (var i = 0; i < cells.length; i++) {
      final cell = cells.denseAt(i);
      final state = fog.isVisible(team, cell.col, cell.row)
          ? FogCellState.visible
          : fog.isExplored(team, cell.col, cell.row)
              ? FogCellState.explored
              : FogCellState.unknown;
      if (state == cell.state) continue;
      cell.state = state;
      world.storeOf<Sprite>().get(cells.entityAt(i))?.region = _regionFor(state);
    }
    if (hideEnemies) _updateEnemies(world);
  }

  String _regionFor(FogCellState state) => switch (state) {
        FogCellState.unknown => unknownRegion,
        FogCellState.explored => exploredRegion,
        FogCellState.visible => clearRegion,
      };

  void _spawnTiles(World world, FogOfWar fog) {
    final scale = cellSize / spriteSize;
    for (var r = 0; r < fog.rows; r++) {
      for (var c = 0; c < fog.cols; c++) {
        final id = world.spawn();
        world.storeOf<FogShadeCell>().set(id, FogShadeCell(c, r, FogCellState.unknown));
        world.storeOf<Position>().set(id, Position((c + 0.5) * cellSize, (r + 0.5) * cellSize));
        world.storeOf<Sprite>().set(
              id,
              Sprite(atlasId, unknownRegion)
                ..scaleX = scale
                ..scaleY = scale
                ..zIndex = zIndex,
            );
      }
    }
  }

  void _updateEnemies(World world) {
    final teams = world.storeOf<Team>();
    final sprites = world.storeOf<Sprite>();
    final hidden = world.storeOf<FogHidden>();
    for (var i = 0; i < teams.length; i++) {
      final e = teams.entityAt(i);
      if (teams.denseAt(i).id == team) continue;
      final seen = canSee(world, team, e);
      final sprite = sprites.get(e);
      if (!seen && sprite != null) {
        hidden.set(e, FogHidden(sprite));
        sprites.remove(e);
      } else if (seen && hidden.has(e)) {
        sprites.set(e, hidden.get(e)!.sprite);
        hidden.remove(e);
      }
    }
  }
}
