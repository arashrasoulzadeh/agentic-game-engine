import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'combat.dart';
import 'grid_navigation.dart';
import 'status.dart';
import 'fog_of_war.dart';
import 'occupancy.dart';
import 'order.dart';
import 'turn_components.dart';
import 'turn_system.dart';

/// Queues [order] for [entity]. Rejected (false) when the entity has no team, or
/// when a turn clock exists and it isn't that team's turn (or the game is over) --
/// orders are only accepted from the side that can act, so a client or agent
/// can't pre-plan the opponent's units.
///
/// A world with **no** turn clock is real-time: any unit with a team may be
/// ordered at any time (who may command which unit is then the caller's rule).
bool submitOrder(World world, EntityId entity, Order order) {
  final state = turnStateOf(world);
  final team = world.storeOf<Team>().get(entity);
  if (team == null) return false;
  if (state != null && (state.winner != null || team.id != state.activeTeam)) return false;
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

  /// Defense a `DefendOrder` grants until the unit's next turn starts.
  final int defendBonus;

  /// Returns the next cell from `from` toward `to`, or null if there is
  /// none. `occupied` tells whether a cell holds another entity.
  final GridPosition? Function(
    World world,
    GridPosition from,
    GridPosition to,
    bool Function(int col, int row) occupied,
  ) nextStep;

  /// Action points to enter `to`. Defaults to the flat `moveCost`; a
  /// navigator-backed system charges the cell's terrain cost instead.
  final int Function(World world, GridPosition to) stepCost;

  OrderSystem({
    this.moveCost = 1,
    int Function(World, GridPosition)? stepCost,
    this.attackCost = 1,
    this.attackRange = 1,
    this.approachTargets = false,
    this.defendBonus = 2,
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
    int defendBonus = 2,
  }) {
    return OrderSystem(
      attackCost: attackCost,
      attackRange: attackRange,
      approachTargets: true,
      defendBonus: defendBonus,
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
    // In id order, not store order: the store's order depends on add/remove
    // history, so a world restored from a snapshot would resolve contested cells
    // differently from the original (see RealtimeOrderSystem.update).
    final ids = [for (var i = 0; i < queues.length; i++) queues.entityAt(i)]..sort();
    for (final entity in ids) {
      final queue = queues.get(entity);
      if (queue == null || teams.get(entity)?.id != state.activeTeam) continue;
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
    if (order is DefendOrder) return _defend(world, entity, order);
    if (order is OverwatchOrder) return _overwatch(world, entity, order);
    return _fail(world, entity, order, OrderFailure.invalidTarget);
  }

  _Result _move(World world, EntityId entity, MoveOrder order) {
    final grid = world.storeOf<GridPosition>();
    final pos = grid.get(entity);
    if (pos == null) return _fail(world, entity, order, OrderFailure.invalidTarget);
    final goal = GridPosition(order.col, order.row);
    final occupied = occupiedBy(grid, entity);

    while (pos.col != goal.col || pos.row != goal.row) {
      final step = nextStep(world, pos, goal, occupied);
      if (step == null) return _fail(world, entity, order, OrderFailure.blocked);
      if (!trySpendActionPoints(world, entity, stepCost(world, step))) {
        return _Result.waiting;
      }
      pos.col = step.col;
      pos.row = step.row;
      world.events.emit(MovedEvent(entity, pos.col, pos.row));
      if (_triggerOverwatch(world, entity)) return _Result.done;
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
    final profile = world.storeOf<AttackProfile>().get(entity);
    final reach = profile?.range ?? attackRange;
    final price = profile?.cost ?? attackCost;
    if (me.chebyshev(target) > reach) {
      if (!approachTargets) return _fail(world, entity, order, OrderFailure.outOfRange);
      // The target's own cell must be walkable for the router, so it is
      // excluded from the occupied set; we stop once in range, before
      // ever entering it.
      final occupied = occupiedBy(grid, entity, ignore: order.target);
      while (me.chebyshev(target) > reach) {
        final step = nextStep(world, me, target, occupied);
        if (step == null) return _fail(world, entity, order, OrderFailure.blocked);
        if (!trySpendActionPoints(world, entity, stepCost(world, step))) {
          return _Result.waiting;
        }
        me.col = step.col;
        me.row = step.row;
        world.events.emit(MovedEvent(entity, me.col, me.row));
        if (_triggerOverwatch(world, entity)) return _Result.done;
      }
    }
    if (!trySpendActionPoints(world, entity, price)) return _Result.waiting;
    world.events.emit(AttackResolvedEvent(entity, order.target));
    return _Result.done;
  }

  _Result _defend(World world, EntityId entity, DefendOrder order) {
    final ap = world.storeOf<ActionPoints>().get(entity);
    if (ap == null) return _fail(world, entity, order, OrderFailure.invalidTarget);
    if (ap.current <= 0) return _Result.waiting;
    if (!trySpendActionPoints(world, entity, ap.current)) return _Result.waiting;
    applyStatus(world, entity, StatusEffect('defending', turns: 1, defense: defendBonus));
    return _Result.done;
  }

  _Result _overwatch(World world, EntityId entity, OverwatchOrder order) {
    final ap = world.storeOf<ActionPoints>().get(entity);
    if (ap == null) return _fail(world, entity, order, OrderFailure.invalidTarget);
    if (ap.current <= 0) return _Result.waiting;
    if (!trySpendActionPoints(world, entity, ap.current)) return _Result.waiting;
    applyStatus(world, entity, StatusEffect(overwatchStatus, turns: 1));
    return _Result.done;
  }

  /// After [mover] enters a cell: the first enemy on overwatch that can see it
  /// and reaches it fires, and its stance ends. Returns true if [mover] died, so
  /// the caller abandons the rest of its path.
  bool _triggerOverwatch(World world, EntityId mover) {
    final teams = world.storeOf<Team>();
    final moverTeam = teams.get(mover)?.id;
    final statuses = world.storeOf<StatusEffects>();
    final grid = world.storeOf<GridPosition>();
    final at = grid.get(mover);
    if (moverTeam == null || at == null) return false;
    for (var i = 0; i < statuses.length; i++) {
      final watcher = statuses.entityAt(i);
      final stance = statuses.denseAt(i);
      if (!stance.has(overwatchStatus) || teams.get(watcher)?.id == moverTeam) continue;
      final from = grid.get(watcher);
      if (from == null) continue;
      final reach = world.storeOf<AttackProfile>().get(watcher)?.range ?? attackRange;
      if (from.chebyshev(at) > reach) continue;
      final watcherTeam = teams.get(watcher)?.id;
      if (watcherTeam != null && !canSee(world, watcherTeam, mover)) continue;
      stance.effects.removeWhere((e) => e.id == overwatchStatus);
      world.events.emit(OverwatchTriggeredEvent(watcher, mover));
      // Resolved directly, not via AttackResolvedEvent: that event is applied at
      // the next flush, after the mover has already finished its whole path.
      resolveAttack(world, watcher, mover);
      return !world.entities.isAlive(mover);
    }
    return false;
  }

  _Result _fail(World world, EntityId entity, Order order, OrderFailure why) {
    world.events.emit(OrderFailedEvent(entity, order, why));
    return _Result.failed;
  }
}

enum _Result { done, waiting, failed }

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
