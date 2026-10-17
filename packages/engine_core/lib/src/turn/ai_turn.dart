import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'combat.dart';
import 'fog_of_war.dart';
import 'grid_navigation.dart';
import 'order.dart';
import 'order_system.dart';
import 'turn_components.dart';
import 'turn_system.dart';

/// Plays one team's whole turn by submitting orders -- the exact path a
/// human tap or an external agent uses (`submitOrder`), so an AI can't
/// do anything a player couldn't, and its decisions are plain JSON
/// orders that show up in `World.toJson()`.
abstract class TurnAI {
  void playTurn(World world, String team);
}

/// Each unit with action points attacks the nearest enemy *its team can
/// see* (so fog applies to the AI equally); with none in sight it holds.
/// Deliberately simple: a baseline opponent, and a reference for writing
/// a smarter `TurnAI`.
class AggressiveAI implements TurnAI {
  @override
  void playTurn(World world, String team) {
    final teams = world.storeOf<Team>();
    final grid = world.storeOf<GridPosition>();
    final points = world.storeOf<ActionPoints>();
    final mine = <EntityId>[];
    final enemies = <EntityId>[];
    for (var i = 0; i < teams.length; i++) {
      final e = teams.entityAt(i);
      if (!grid.has(e)) continue;
      if (teams.denseAt(i).id == team) {
        if ((points.get(e)?.current ?? 0) > 0) mine.add(e);
      } else if (canSee(world, team, e)) {
        enemies.add(e);
      }
    }
    for (final unit in mine) {
      final from = grid.get(unit)!;
      EntityId? best;
      var bestDist = 1 << 30;
      for (final enemy in enemies) {
        final d = from.chebyshev(grid.get(enemy)!);
        if (d < bestDist) {
          bestDist = d;
          best = enemy;
        }
      }
      if (best == null) continue;
      world.storeOf<OrderQueue>().get(unit)?.orders.clear();
      submitOrder(world, unit, AttackOrder(best));
    }
  }
}

/// A more deliberate opponent than [AggressiveAI], built from four independent
/// behaviours you can switch off:
///
/// * **Focus fire** ([focusFire]): everyone goes for the same target - the visible
///   enemy with the fewest hit points - so damage kills instead of spreading.
/// * **Retreat** ([retreatBelow]): a unit under that fraction of its max hp, with
///   enemies in sight, moves to the reachable cell farthest from them instead
///   of attacking (needs a [navigator]).
/// * **Explore** ([explore]): with nothing in sight and fog of war in play,
///   units head for the nearest cell their team has not explored yet, each
///   claiming a different one so they fan out (needs a [navigator]).
/// * **Hold** ([defendWhenIdle]): with nothing to attack or explore, a unit
///   braces with a `DefendOrder` rather than wasting its points.
///
/// Like every [TurnAI] it acts only through `submitOrder`, and sees only what its
/// team can see.
class TacticalAI implements TurnAI {
  TacticalAI({
    this.navigator,
    this.focusFire = true,
    this.retreatBelow = 0.3,
    this.explore = true,
    this.defendWhenIdle = false,
  });

  /// Grid rules for retreat and exploration; those behaviours are skipped without one.
  final GridNavigator? navigator;
  final bool focusFire;

  /// Hit-point fraction (0..1) below which a unit retreats. 0 disables it.
  final double retreatBelow;
  final bool explore;
  final bool defendWhenIdle;

  @override
  void playTurn(World world, String team) {
    final teams = world.storeOf<Team>();
    final grid = world.storeOf<GridPosition>();
    final points = world.storeOf<ActionPoints>();
    final mine = <EntityId>[];
    final enemies = <EntityId>[];
    for (var i = 0; i < teams.length; i++) {
      final e = teams.entityAt(i);
      if (!grid.has(e)) continue;
      if (teams.denseAt(i).id == team) {
        if ((points.get(e)?.current ?? 0) > 0) mine.add(e);
      } else if (canSee(world, team, e)) {
        enemies.add(e);
      }
    }
    if (mine.isEmpty) return;
    for (final unit in mine) {
      world.storeOf<OrderQueue>().get(unit)?.orders.clear();
    }
    if (enemies.isEmpty) {
      _idle(world, team, mine);
      return;
    }

    final shared = focusFire ? _weakest(world, mine, enemies) : null;
    for (final unit in mine) {
      if (_shouldRetreat(world, unit) && _retreat(world, unit, enemies)) continue;
      final target = shared ?? _nearest(world, unit, enemies);
      submitOrder(world, unit, AttackOrder(target));
    }
  }

  EntityId _weakest(World world, List<EntityId> mine, List<EntityId> enemies) {
    final stats = world.storeOf<UnitStats>();
    final grid = world.storeOf<GridPosition>();
    var cx = 0.0, cy = 0.0;
    for (final m in mine) {
      cx += grid.get(m)!.col;
      cy += grid.get(m)!.row;
    }
    cx /= mine.length;
    cy /= mine.length;
    double distance(EntityId e) {
      final p = grid.get(e)!;
      return (p.col - cx).abs() + (p.row - cy).abs();
    }

    EntityId best = enemies.first;
    for (final e in enemies.skip(1)) {
      final hpE = stats.get(e)?.hp ?? 1 << 30, hpB = stats.get(best)?.hp ?? 1 << 30;
      if (hpE < hpB || (hpE == hpB && distance(e) < distance(best))) best = e;
    }
    return best;
  }

  EntityId _nearest(World world, EntityId unit, List<EntityId> enemies) {
    final grid = world.storeOf<GridPosition>();
    final from = grid.get(unit)!;
    EntityId best = enemies.first;
    for (final e in enemies.skip(1)) {
      if (from.chebyshev(grid.get(e)!) < from.chebyshev(grid.get(best)!)) best = e;
    }
    return best;
  }

  bool _shouldRetreat(World world, EntityId unit) {
    if (navigator == null || retreatBelow <= 0) return false;
    final stats = world.storeOf<UnitStats>().get(unit);
    return stats != null && stats.hp / stats.maxHp < retreatBelow;
  }

  bool _occupied(World world, EntityId self, int col, int row) {
    final grid = world.storeOf<GridPosition>();
    for (var i = 0; i < grid.length; i++) {
      final g = grid.denseAt(i);
      if (grid.entityAt(i) != self && g.col == col && g.row == row) return true;
    }
    return false;
  }

  bool _retreat(World world, EntityId unit, List<EntityId> enemies) {
    final grid = world.storeOf<GridPosition>();
    final from = grid.get(unit)!;
    int threat(int col, int row) {
      var nearest = 1 << 30;
      for (final e in enemies) {
        final p = grid.get(e)!;
        final d = (col - p.col).abs() > (row - p.row).abs() ? (col - p.col).abs() : (row - p.row).abs();
        if (d < nearest) nearest = d;
      }
      return nearest;
    }

    final budget = world.storeOf<ActionPoints>().get(unit)!.current;
    final options = navigator!.reachable(from, budget, blocked: (c, r) => _occupied(world, unit, c, r));
    var bestScore = threat(from.col, from.row);
    (int, int)? best;
    for (final cell in options.keys) {
      final score = threat(cell.$1, cell.$2);
      if (score > bestScore) {
        bestScore = score;
        best = cell;
      }
    }
    if (best == null) return false;
    return submitOrder(world, unit, MoveOrder(best.$1, best.$2));
  }

  void _idle(World world, String team, List<EntityId> mine) {
    final fog = fogOf(world);
    final claimed = <int>{};
    for (final unit in mine) {
      if (explore && navigator != null && fog != null) {
        final cell = _unexplored(world, team, unit, fog, claimed);
        if (cell != null && submitOrder(world, unit, MoveOrder(cell.$1, cell.$2))) continue;
      }
      if (defendWhenIdle) submitOrder(world, unit, const DefendOrder());
    }
  }

  (int, int)? _unexplored(World world, String team, EntityId unit, FogOfWar fog, Set<int> claimed) {
    final from = world.storeOf<GridPosition>().get(unit)!;
    final explored = fog.explored[team] ?? const <int>{};
    (int, int)? best;
    var bestDist = 1 << 30;
    for (var r = 0; r < fog.rows; r++) {
      for (var c = 0; c < fog.cols; c++) {
        final key = fog.key(c, r);
        if (explored.contains(key) || claimed.contains(key)) continue;
        final d = (c - from.col).abs() > (r - from.row).abs() ? (c - from.col).abs() : (r - from.row).abs();
        if (d >= bestDist) continue;
        if (navigator!.findPath(from, GridPosition(c, r),
                blocked: (cc, rr) => _occupied(world, unit, cc, rr)) ==
            null) {
          continue;
        }
        best = (c, r);
        bestDist = d;
      }
    }
    if (best != null) claimed.add(fog.key(best.$1, best.$2));
    return best;
  }
}

/// Runs a [TurnAI] for each team in [controllers] when it is that
/// team's turn, then ends the turn once nothing it queued can still
/// make progress.
///
/// Register it *after* `OrderSystem`: the AI plans on one tick and the
/// orders execute on the next, so by the time this system looks again
/// anything affordable has run, and whatever is still queued is waiting
/// on action points that won't come until next turn -- the signal to
/// end the turn.
class AITurnSystem extends System {
  final Map<String, TurnAI> controllers;
  String? _plannedKey;

  AITurnSystem(this.controllers);

  @override
  String get name => 'aiTurn';

  @override
  void update(World world, double dt) {
    final state = turnStateOf(world);
    if (state == null || state.winner != null) return;
    final ai = controllers[state.activeTeam];
    if (ai == null) return;

    final key = '${state.round}:${state.activeTeam}';
    if (_plannedKey != key) {
      _plannedKey = key;
      ai.playTurn(world, state.activeTeam);
      return;
    }
    if (!_canStillAct(world, state.activeTeam)) endTurn(world);
  }

  bool _canStillAct(World world, String team) {
    final queues = world.storeOf<OrderQueue>();
    final teams = world.storeOf<Team>();
    final points = world.storeOf<ActionPoints>();
    for (var i = 0; i < queues.length; i++) {
      final e = queues.entityAt(i);
      if (queues.denseAt(i).orders.isEmpty || teams.get(e)?.id != team) continue;
      if ((points.get(e)?.current ?? 0) > 0) return true;
    }
    return false;
  }
}
