import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'order.dart';
import 'turn_components.dart';

/// How far a unit sees, in cells (circular radius).
class Vision {
  int range;
  Vision(this.range);

  Map<String, dynamic> toJson() => {'range': range};
  factory Vision.fromJson(Map<String, dynamic> json) => Vision((json['range'] as num).toInt());
}

/// Per-team visibility of a [cols] x [rows] grid, as world state so an
/// agent sees exactly what a team sees (the fairness point of fog for
/// AI opponents) and saves restore explored territory.
///
/// Cells are stored as `row * cols + col` ints. [visible] is recomputed
/// every tick by `VisionSystem`; [explored] only ever grows.
class FogOfWar {
  final int cols;
  final int rows;
  final Map<String, Set<int>> visible;
  final Map<String, Set<int>> explored;

  FogOfWar(this.cols, this.rows, {Map<String, Set<int>>? visible, Map<String, Set<int>>? explored})
      : visible = visible ?? {},
        explored = explored ?? {};

  int key(int col, int row) => row * cols + col;

  bool isVisible(String team, int col, int row) =>
      visible[team]?.contains(key(col, row)) ?? false;

  bool isExplored(String team, int col, int row) =>
      explored[team]?.contains(key(col, row)) ?? false;

  Map<String, dynamic> toJson() => {
        'cols': cols,
        'rows': rows,
        'visible': {for (final e in visible.entries) e.key: (e.value.toList()..sort())},
        'explored': {for (final e in explored.entries) e.key: (e.value.toList()..sort())},
      };

  factory FogOfWar.fromJson(Map<String, dynamic> json) {
    Map<String, Set<int>> read(Object? raw) => {
          for (final e in ((raw as Map?) ?? const {}).entries)
            e.key as String: {for (final v in e.value as List) (v as num).toInt()},
        };
    return FogOfWar(
      (json['cols'] as num).toInt(),
      (json['rows'] as num).toInt(),
      visible: read(json['visible']),
      explored: read(json['explored']),
    );
  }
}

/// True if no cell strictly between the two points blocks sight.
/// Bresenham line; the endpoints themselves never block, so you can
/// always see the wall you're looking at.
bool hasGridLineOfSight(
  int c0,
  int r0,
  int c1,
  int r1,
  bool Function(int col, int row) blocksSight,
) {
  var c = c0, r = r0;
  final dc = (c1 - c0).abs(), dr = -(r1 - r0).abs();
  final sc = c0 < c1 ? 1 : -1, sr = r0 < r1 ? 1 : -1;
  var err = dc + dr;
  while (c != c1 || r != r1) {
    final e2 = 2 * err;
    if (e2 >= dr) {
      err += dr;
      c += sc;
    }
    if (e2 <= dc) {
      err += dc;
      r += sr;
    }
    if ((c != c1 || r != r1) && blocksSight(c, r)) return false;
  }
  return true;
}

/// Recomputes each team's visible cells from its units' `Vision` and
/// `GridPosition`, and accumulates explored cells. Needs a `FogOfWar`
/// component on some entity.
class VisionSystem extends System {
  /// Cells that stop sight (walls). Distinct from movement cost on
  /// purpose: a lake is impassable but you can see across it.
  final bool Function(int col, int row) blocksSight;

  VisionSystem({this.blocksSight = _never});

  static bool _never(int c, int r) => false;

  @override
  String get name => 'vision';

  @override
  void update(World world, double dt) {
    final fogs = world.storeOf<FogOfWar>();
    if (fogs.length == 0) return;
    final fog = fogs.denseAt(0);
    final teams = world.storeOf<Team>();
    final grid = world.storeOf<GridPosition>();
    final vision = world.storeOf<Vision>();

    for (final set in fog.visible.values) {
      set.clear();
    }
    for (var i = 0; i < vision.length; i++) {
      final e = vision.entityAt(i);
      final team = teams.get(e)?.id;
      final pos = grid.get(e);
      if (team == null || pos == null) continue;
      final seen = fog.visible.putIfAbsent(team, () => {});
      final range = vision.denseAt(i).range;
      for (var r = pos.row - range; r <= pos.row + range; r++) {
        for (var c = pos.col - range; c <= pos.col + range; c++) {
          if (c < 0 || r < 0 || c >= fog.cols || r >= fog.rows) continue;
          final dc = c - pos.col, dr = r - pos.row;
          if (dc * dc + dr * dr > range * range) continue;
          if (hasGridLineOfSight(pos.col, pos.row, c, r, blocksSight)) {
            seen.add(fog.key(c, r));
          }
        }
      }
    }
    for (final entry in fog.visible.entries) {
      fog.explored.putIfAbsent(entry.key, () => {}).addAll(entry.value);
    }
  }
}

/// The world's fog, or null when the game has none (fog is optional).
FogOfWar? fogOf(World world) {
  final s = world.storeOf<FogOfWar>();
  return s.length == 0 ? null : s.denseAt(0);
}

/// Whether [team] currently sees [entity]. True when the game has no
/// fog, or the entity is on the team's own side.
bool canSee(World world, String team, EntityId entity) {
  final fog = fogOf(world);
  if (fog == null) return true;
  if (world.storeOf<Team>().get(entity)?.id == team) return true;
  final pos = world.storeOf<GridPosition>().get(entity);
  return pos != null && fog.isVisible(team, pos.col, pos.row);
}
