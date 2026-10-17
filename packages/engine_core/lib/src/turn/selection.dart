import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import '../physics/position.dart';
import 'order.dart';
import 'order_system.dart';
import 'turn_components.dart';
import 'turn_system.dart';

/// Marks an entity as currently selected by the local player. A marker
/// (no fields) so selection is ordinary world state: an agent can read
/// it, and a save/replay restores it.
class Selected {
  const Selected();

  Map<String, dynamic> toJson() => {};
  factory Selected.fromJson(Map<String, dynamic> json) => const Selected();
}

/// Selected entities, in storage order.
List<EntityId> selectedEntities(World world) {
  final store = world.storeOf<Selected>();
  return [for (var i = 0; i < store.length; i++) store.entityAt(i)];
}

void clearSelection(World world) {
  for (final e in selectedEntities(world)) {
    world.storeOf<Selected>().remove(e);
  }
}

bool _selectable(World world, EntityId e, TurnState state) =>
    world.storeOf<Team>().get(e)?.id == state.activeTeam &&
    world.storeOf<GridPosition>().has(e);

/// Selects the active team's unit standing on ([col], [row]). Only the
/// side whose turn it is can be selected, so the UI can't hand the
/// player an opponent's unit. With no unit there, the selection is
/// left untouched and null returned (so a stray tap on empty ground can
/// be interpreted as a move command by the caller). [additive] keeps
/// the existing selection (shift/ctrl-click).
EntityId? selectAtCell(World world, int col, int row, {bool additive = false}) {
  final state = turnStateOf(world);
  if (state == null) return null;
  final grid = world.storeOf<GridPosition>();
  for (var i = 0; i < grid.length; i++) {
    final e = grid.entityAt(i);
    final p = grid.denseAt(i);
    if (p.col == col && p.row == row && _selectable(world, e, state)) {
      if (!additive) clearSelection(world);
      world.storeOf<Selected>().set(e, const Selected());
      return e;
    }
  }
  return null;
}

/// Box-selects every active-team unit with a cell in the inclusive
/// rectangle spanned by the two corners (given in any order). Returns
/// how many were selected; an empty box leaves the selection alone.
int selectInBox(World world, int col0, int row0, int col1, int row1, {bool additive = false}) {
  final state = turnStateOf(world);
  if (state == null) return 0;
  final c0 = col0 < col1 ? col0 : col1, c1 = col0 < col1 ? col1 : col0;
  final r0 = row0 < row1 ? row0 : row1, r1 = row0 < row1 ? row1 : row0;
  final grid = world.storeOf<GridPosition>();
  final hits = <EntityId>[
    for (var i = 0; i < grid.length; i++)
      if (grid.denseAt(i).col >= c0 &&
          grid.denseAt(i).col <= c1 &&
          grid.denseAt(i).row >= r0 &&
          grid.denseAt(i).row <= r1 &&
          _selectable(world, grid.entityAt(i), state))
        grid.entityAt(i),
  ];
  if (hits.isEmpty) return 0;
  if (!additive) clearSelection(world);
  for (final e in hits) {
    world.storeOf<Selected>().set(e, const Selected());
  }
  return hits.length;
}

/// Orders every selected unit toward ([col], [row]): an attack if an
/// enemy stands there, otherwise a move. Returns how many orders were
/// accepted. [replace] drops each unit's queued orders first, matching
/// the usual "new click overrides" feel; false appends (shift-queue).
int commandSelected(World world, int col, int row, {bool replace = true}) {
  final state = turnStateOf(world);
  if (state == null) return 0;
  final grid = world.storeOf<GridPosition>();
  final teams = world.storeOf<Team>();
  EntityId? enemy;
  for (var i = 0; i < grid.length; i++) {
    final e = grid.entityAt(i);
    final t = teams.get(e);
    if (grid.denseAt(i).col == col &&
        grid.denseAt(i).row == row &&
        t != null &&
        t.id != state.activeTeam) {
      enemy = e;
      break;
    }
  }
  var accepted = 0;
  for (final e in selectedEntities(world)) {
    if (!_selectable(world, e, state)) continue;
    if (replace) world.storeOf<OrderQueue>().get(e)?.orders.clear();
    final order = enemy != null ? AttackOrder(enemy) : MoveOrder(col, row);
    if (submitOrder(world, e, order)) accepted++;
  }
  return accepted;
}

/// Keeps `Position` (world pixels, what renderers read) in step with
/// `GridPosition` (cells, what rules read), placing the entity at its
/// cell's center. The grid stays the single source of truth; nothing
/// else should write `Position` for grid units.
class GridToWorldSystem extends System {
  final double cellSize;
  GridToWorldSystem(this.cellSize);

  @override
  String get name => 'gridToWorld';

  @override
  void update(World world, double dt) {
    final grid = world.storeOf<GridPosition>();
    final positions = world.storeOf<Position>();
    for (var i = 0; i < grid.length; i++) {
      final p = positions.get(grid.entityAt(i));
      if (p == null) continue;
      final g = grid.denseAt(i);
      p.x = (g.col + 0.5) * cellSize;
      p.y = (g.row + 0.5) * cellSize;
    }
  }
}
