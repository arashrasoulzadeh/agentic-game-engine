import '../ecs/component_store.dart';
import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'grid_navigation.dart';
import 'fog_of_war.dart';
import 'order.dart';
import 'turn_components.dart';
import 'turn_system.dart';

/// Queues [order] for [entity]. Rejected (false) when it isn't the
/// entity's team's turn or the entity has no team -- orders are only
/// accepted from the side that can act, so a client or agent can't
/// pre-plan the opponent's units.
bool submitOrder(World world, EntityId entity, Order order) {
  final state = turnStateOf(world);
  final team = world.storeOf<Team>().get(entity);
  if (state == null || state.winner != null || team == null || team.id != state.activeTeam) {
    return false;
  }
  final store = world.storeOf<OrderQueue>();
  var queue = store.get(entity);
  if (queue == null) {
    queue = OrderQueue();
    store.set(entity, queue);
  }
  queue.orders.add(order);
  return true;
}

/// Executes the front order of every active-team entity each tick.
///
/// Movement is greedy 4-directional (column first), one cell per step at
/// [moveCost] action points. Smarter routing replaces [nextStep] --
/// kept as an injectable function so pathfinding (phase 3) plugs in
/// without changing order handling.
class OrderSystem extends System {
  final int moveCost;
  final int attackCost;
  final int attackRange;

  /// When true, an attack on a target beyond [attackRange] first walks
  /// toward it (spending move cost per step) instead of failing with
  /// `outOfRange`. Off for the plain constructor so existing callers
  /// keep strict range semantics; on for `withNavigator`, where a tap
  /// on a distant enemy should mean "go get it".
  final bool approachTargets;

  /// Returns the next cell from [from] toward [to], or null if there is
  /// none. [occupied] tells whether a cell holds another entity.
  final GridPosition? Function(
    World world,
    GridPosition from,
    GridPosition to,
    bool Function(int col, int row) occupied,
  ) nextStep;

  /// Action points to enter [to]. Defaults to the flat [moveCost]; a
  /// navigator-backed system charges the cell's terrain cost instead.
  final int Function(World world, GridPosition to) stepCost;

  OrderSystem({
    this.moveCost = 1,
    int Function(World, GridPosition)? stepCost,
    this.attackCost = 1,
    this.attackRange = 1,
    this.approachTargets = false,
    GridPosition? Function(World, GridPosition, GridPosition, bool Function(int, int))? nextStep,
  })  : nextStep = nextStep ?? _greedyStep,
        stepCost = stepCost ?? ((_, __) => moveCost);

  /// An [OrderSystem] that routes with [nav] (weighted, 8-way, around
  /// other units) and charges each step the terrain cost of the cell
  /// entered, so a 3-cost forest tile really costs 3 action points.
  factory OrderSystem.withNavigator(
    GridNavigator nav, {
    int attackCost = 1,
    int attackRange = 1,
  }) {
    return OrderSystem(
      attackCost: attackCost,
      attackRange: attackRange,
      approachTargets: true,
      stepCost: (_, to) => nav.terrainCost(to.col, to.row) ?? 1,
      nextStep: (world, from, to, occupied) {
        final path = nav.findPath(from, to, blocked: occupied);
        return path == null || path.isEmpty ? null : path.first;
      },
    );
  }

  @override
  String get name => 'orders';

  @override
  void update(World world, double dt) {
    final state = turnStateOf(world);
    if (state == null) return;
    final queues = world.storeOf<OrderQueue>();
    final teams = world.storeOf<Team>();
    for (var i = 0; i < queues.length; i++) {
      final entity = queues.entityAt(i);
      if (teams.get(entity)?.id != state.activeTeam) continue;
      final queue = queues.denseAt(i);
      while (queue.orders.isNotEmpty) {
        final result = _run(world, entity, queue.orders.first);
        if (result == _Result.waiting) break;
        queue.orders.removeAt(0);
      }
    }
  }

  _Result _run(World world, EntityId entity, Order order) {
    if (order is MoveOrder) return _move(world, entity, order);
    if (order is AttackOrder) return _attack(world, entity, order);
    return _fail(world, entity, order, OrderFailure.invalidTarget);
  }

  _Result _move(World world, EntityId entity, MoveOrder order) {
    final grid = world.storeOf<GridPosition>();
    final pos = grid.get(entity);
    if (pos == null) return _fail(world, entity, order, OrderFailure.invalidTarget);
    final goal = GridPosition(order.col, order.row);
    final occupied = _occupiedBy(grid, entity);

    while (pos.col != goal.col || pos.row != goal.row) {
      final step = nextStep(world, pos, goal, occupied);
      if (step == null) return _fail(world, entity, order, OrderFailure.blocked);
      if (!trySpendActionPoints(world, entity, stepCost(world, step))) {
        return _Result.waiting;
      }
      pos.col = step.col;
      pos.row = step.row;
      world.events.emit(MovedEvent(entity, pos.col, pos.row));
    }
    return _Result.done;
  }

  _Result _attack(World world, EntityId entity, AttackOrder order) {
    final grid = world.storeOf<GridPosition>();
    final me = grid.get(entity);
    final target = grid.get(order.target);
    final friendly = world.storeOf<Team>().get(order.target)?.id ==
        world.storeOf<Team>().get(entity)?.id;
    if (me == null || target == null || friendly || !world.entities.isAlive(order.target)) {
      return _fail(world, entity, order, OrderFailure.invalidTarget);
    }
    final myTeam = world.storeOf<Team>().get(entity)?.id;
    if (myTeam != null && !canSee(world, myTeam, order.target)) {
      return _fail(world, entity, order, OrderFailure.invalidTarget);
    }
    if (me.chebyshev(target) > attackRange) {
      if (!approachTargets) return _fail(world, entity, order, OrderFailure.outOfRange);
      // The target's own cell must be walkable for the router, so it is
      // excluded from the occupied set; we stop once in range, before
      // ever entering it.
      final occupied = _occupiedBy(grid, entity, ignore: order.target);
      while (me.chebyshev(target) > attackRange) {
        final step = nextStep(world, me, target, occupied);
        if (step == null) return _fail(world, entity, order, OrderFailure.blocked);
        if (!trySpendActionPoints(world, entity, stepCost(world, step))) {
          return _Result.waiting;
        }
        me.col = step.col;
        me.row = step.row;
        world.events.emit(MovedEvent(entity, me.col, me.row));
      }
    }
    if (!trySpendActionPoints(world, entity, attackCost)) return _Result.waiting;
    world.events.emit(AttackResolvedEvent(entity, order.target));
    return _Result.done;
  }

  _Result _fail(World world, EntityId entity, Order order, OrderFailure why) {
    world.events.emit(OrderFailedEvent(entity, order, why));
    return _Result.failed;
  }
}

enum _Result { done, waiting, failed }

bool Function(int, int) _occupiedBy(
  ComponentStore<GridPosition> grid,
  EntityId self, {
  EntityId? ignore,
}) {
  return (c, r) {
    for (var i = 0; i < grid.length; i++) {
      final o = grid.denseAt(i);
      final e = grid.entityAt(i);
      if (e != self && e != ignore && o.col == c && o.row == r) return true;
    }
    return false;
  };
}

GridPosition? _greedyStep(
  World world,
  GridPosition from,
  GridPosition to,
  bool Function(int, int) occupied,
) {
  final dc = (to.col - from.col).sign;
  final dr = (to.row - from.row).sign;
  final candidates = [
    if (dc != 0) GridPosition(from.col + dc, from.row),
    if (dr != 0) GridPosition(from.col, from.row + dr),
  ];
  for (final c in candidates) {
    if (!occupied(c.col, c.row)) return c;
  }
  return null;
}
