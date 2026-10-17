import '../ecs/component_store.dart';
import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'carry.dart';
import 'combat.dart';
import 'fog_of_war.dart';
import 'grid_navigation.dart';
import 'objectives.dart';
import 'order.dart';
import 'occupancy.dart';
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
    mine.sort();
    enemies.sort();
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
    // Id order, not store order, so the same position always yields the same
    // orders (store order depends on add/remove history; see RealtimeOrderSystem).
    mine.sort();
    enemies.sort();
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

  bool _retreat(World world, EntityId unit, List<EntityId> enemies) =>
      _retreatFrom(world, unit, world.storeOf<GridPosition>().get(unit)!, enemies, navigator!);

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
                blocked: occupiedBy(world.storeOf<GridPosition>(), unit)) ==
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

/// An AI that plays for the map's [Objective]s rather than just for kills:
///
/// * A unit standing on an objective its team owns **holds it** when an enemy is
///   close enough to take it ([holdRadius]); otherwise it is free to move.
/// * Units with an enemy in [engageRange] fight it (nearest enemy; units already
///   engaged don't wander off).
/// * Everyone else walks toward the nearest objective the team doesn't own,
///   spreading out so they don't all pick the same one while others remain.
///
/// It also plays the carry-and-escort rules when the map has them:
///
/// * A unit **carrying a flag** heads for its team's `DeliveryZone`.
/// * The nearest free unit goes to pick up each enemy flag lying on the ground, one
///   unit per flag.
/// * When an enemy is **carrying your flag**, units nearby chase and attack the
///   carrier (killing it drops the flag).
/// * Your **`Vip`** stays out of reach: it retreats to the reachable cell farthest
///   from the enemy when one is within [engageRange] + 1, instead of fighting.
///
/// Combat is delegated to a [TacticalAI]-style attack, so it still only targets
/// what the team can see. Needs a [navigator] to pick reachable destinations.
class ObjectiveAI implements TurnAI {
  ObjectiveAI({
    required this.navigator,
    this.engageRange = 4,
    this.holdRadius = 5,
  });

  final GridNavigator navigator;

  /// Chebyshev distance within which a unit prefers fighting to marching.
  final int engageRange;

  /// How near an enemy must be before a garrison refuses to leave its objective.
  final int holdRadius;

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
    mine.sort();
    enemies.sort();
    for (final unit in mine) {
      world.storeOf<OrderQueue>().get(unit)?.orders.clear();
    }

    final objectives = world.storeOf<Objective>();
    final targets = objectivesToTake(world, team);
    final claimed = <EntityId>{};
    final claimedFlags = <EntityId>{};
    for (final unit in mine) {
      final at = grid.get(unit)!;
      final nearEnemy = _nearest(grid, at, enemies);
      final nearDist = nearEnemy == null ? 1 << 30 : at.chebyshev(grid.get(nearEnemy)!);

      if (_playCarryAndEscort(world, team, unit, at, enemies, claimedFlags)) continue;

      final onOwned = _objectiveAt(objectives, at, team);
      if (onOwned && nearDist <= holdRadius) {
        if (nearDist <= engageRange) {
          submitOrder(world, unit, AttackOrder(nearEnemy!));
        } else {
          submitOrder(world, unit, const DefendOrder());
        }
        continue;
      }
      if (nearEnemy != null && nearDist <= engageRange) {
        submitOrder(world, unit, AttackOrder(nearEnemy));
        continue;
      }
      final goal = _pickObjective(at, targets, claimed);
      if (goal != null) {
        claimed.add(goal.$1);
        submitOrder(world, unit, MoveOrder(goal.$2.col, goal.$2.row));
      } else if (nearEnemy != null) {
        submitOrder(world, unit, AttackOrder(nearEnemy));
      }
    }
  }

  /// Handles flags, zones and the Vip for [unit]; true if it issued an order (so
  /// the ordinary objective logic is skipped for this unit).
  bool _playCarryAndEscort(
    World world,
    String team,
    EntityId unit,
    GridPosition at,
    List<EntityId> enemies,
    Set<EntityId> claimedFlags,
  ) {
    final flags = world.storeOf<Flag>();
    final grid = world.storeOf<GridPosition>();

    // 1. The Vip keeps away from danger.
    if (world.storeOf<Vip>().has(unit) && enemies.isNotEmpty) {
      final near = _nearest(grid, at, enemies)!;
      if (at.chebyshev(grid.get(near)!) <= engageRange + 1 && _retreatFrom(world, unit, at, enemies, navigator)) {
        return true;
      }
    }

    // 2. A carrier runs for home.
    for (var i = 0; i < flags.length; i++) {
      if (flags.denseAt(i).carrier != unit) continue;
      final zones = world.storeOf<DeliveryZone>();
      for (var z = 0; z < zones.length; z++) {
        final zone = zones.denseAt(z);
        if (zone.team != team) continue;
        return submitOrder(world, unit, MoveOrder(zone.col, zone.row));
      }
    }

    // 3. Chase whoever is carrying our flag.
    for (var i = 0; i < flags.length; i++) {
      final f = flags.denseAt(i);
      final holder = f.carrier;
      if (f.homeTeam != team || holder == null || !world.entities.isAlive(holder)) continue;
      if (world.storeOf<Team>().get(holder)?.id == team || !canSee(world, team, holder)) continue;
      final hp = grid.get(holder);
      if (hp != null && at.chebyshev(hp) <= holdRadius + engageRange) {
        return submitOrder(world, unit, AttackOrder(holder));
      }
    }

    // 4. Fetch enemy flags lying on the ground, one unit each (the nearest free one).
    for (var i = 0; i < flags.length; i++) {
      final f = flags.denseAt(i);
      final id = flags.entityAt(i);
      if (f.homeTeam == team || f.carrier != null || claimedFlags.contains(id)) continue;
      if (world.storeOf<Vip>().has(unit)) continue;
      if (_isNearestTo(world, team, unit, f.col, f.row)) {
        claimedFlags.add(id);
        return submitOrder(world, unit, MoveOrder(f.col, f.row));
      }
    }
    return false;
  }

  /// True if [unit] is the closest of this team's units with action points to
  /// ([col], [row]) (ties go to the lowest id, so the answer is deterministic).
  bool _isNearestTo(World world, String team, EntityId unit, int col, int row) {
    final teams = world.storeOf<Team>();
    final grid = world.storeOf<GridPosition>();
    final points = world.storeOf<ActionPoints>();
    final cell = GridPosition(col, row);
    EntityId? best;
    var bestD = 1 << 30;
    for (var i = 0; i < teams.length; i++) {
      final e = teams.entityAt(i);
      if (teams.denseAt(i).id != team || (points.get(e)?.current ?? 0) <= 0 || world.storeOf<Vip>().has(e)) continue;
      final p = grid.get(e);
      if (p == null) continue;
      final d = p.chebyshev(cell);
      if (d < bestD || (d == bestD && e < best!)) {
        bestD = d;
        best = e;
      }
    }
    return best == unit;
  }

  bool _objectiveAt(ComponentStore<Objective> objectives, GridPosition at, String team) {
    for (var i = 0; i < objectives.length; i++) {
      final o = objectives.denseAt(i);
      if (o.col == at.col && o.row == at.row && o.owner == team) return true;
    }
    return false;
  }

  EntityId? _nearest(ComponentStore<GridPosition> grid, GridPosition from, List<EntityId> enemies) {
    EntityId? best;
    var bestD = 1 << 30;
    for (final e in enemies) {
      final d = from.chebyshev(grid.get(e)!);
      if (d < bestD) {
        bestD = d;
        best = e;
      }
    }
    return best;
  }

  /// The nearest objective to take, preferring ones no teammate has been sent to;
  /// when all are claimed, the nearest anyway (several units may converge).
  (EntityId, Objective)? _pickObjective(
    GridPosition from,
    List<(EntityId, Objective)> targets,
    Set<EntityId> claimed,
  ) {
    (EntityId, Objective)? best;
    var bestD = 1 << 30;
    for (final pass in [true, false]) {
      for (final t in targets) {
        if (pass && claimed.contains(t.$1)) continue;
        final d = from.chebyshev(GridPosition(t.$2.col, t.$2.row));
        if (d < bestD && navigator.findPath(from, GridPosition(t.$2.col, t.$2.row)) != null) {
          bestD = d;
          best = t;
        }
      }
      if (best != null) break;
    }
    return best;
  }
}

/// Moves [unit] to the cell it can reach with its action points that is farthest
/// from the nearest of [enemies], if that is an improvement on staying put.
/// Returns whether a move order was issued. Shared by the AIs' retreat behaviours.
bool _retreatFrom(
  World world,
  EntityId unit,
  GridPosition from,
  List<EntityId> enemies,
  GridNavigator navigator,
) {
  final grid = world.storeOf<GridPosition>();
  int threat(int col, int row) {
    var nearest = 1 << 30;
    for (final e in enemies) {
      final p = grid.get(e)!;
      final d = (col - p.col).abs() > (row - p.row).abs() ? (col - p.col).abs() : (row - p.row).abs();
      if (d < nearest) nearest = d;
    }
    return nearest;
  }

  final budget = world.storeOf<ActionPoints>().get(unit)?.current ?? 0;
  final options = navigator.reachable(from, budget, blocked: occupiedBy(grid, unit));
  var bestScore = threat(from.col, from.row);
  (int, int)? best;
  for (final cell in options.keys) {
    final score = threat(cell.$1, cell.$2);
    if (score > bestScore) {
      bestScore = score;
      best = cell;
    }
  }
  return best != null && submitOrder(world, unit, MoveOrder(best.$1, best.$2));
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
