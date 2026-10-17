import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'combat.dart';
import 'flow_field.dart';
import 'fog_of_war.dart';
import 'occupancy.dart';
import 'order.dart';
import 'turn_components.dart';

/// How fast a real-time unit acts. Real-time play has no action points: speed and
/// cooldowns are the budget.
class RealtimeStats {
  /// Cells per second.
  double speed;

  /// Seconds between attacks.
  double attackInterval;

  /// Fraction of the next step already walked (0..1); carries over between ticks so
  /// a slow unit still moves at exactly [speed] on average.
  double moveProgress;

  /// Seconds until the unit may attack again.
  double cooldown;

  RealtimeStats({this.speed = 2, this.attackInterval = 1, this.moveProgress = 0, this.cooldown = 0});

  Map<String, dynamic> toJson() => {
        'speed': speed,
        'attackInterval': attackInterval,
        'moveProgress': moveProgress,
        'cooldown': cooldown,
      };
  factory RealtimeStats.fromJson(Map<String, dynamic> json) => RealtimeStats(
        speed: (json['speed'] as num?)?.toDouble() ?? 2,
        attackInterval: (json['attackInterval'] as num?)?.toDouble() ?? 1,
        moveProgress: (json['moveProgress'] as num?)?.toDouble() ?? 0,
        cooldown: (json['cooldown'] as num?)?.toDouble() ?? 0,
      );
}

/// Executes `OrderQueue`s continuously, driven by `dt` instead of turns.
///
/// Movement follows shared [FlowField]s (one per destination, cached), so a
/// hundred units sent to one place cost one search. Attacks happen on a
/// per-unit cooldown and land immediately (`resolveAttack`); an attack order keeps
/// the unit chasing and hitting its target until the target is gone.
///
/// It is **deterministic**: given the same world and the same `dt` sequence it
/// produces the same result, which is what lockstep multiplayer and replays need.
/// Run it with a fixed timestep (`GameConfig.fixedTimestepSeconds`), never raw
/// frame times. Orders are submitted with the same `submitOrder`/selection calls
/// as turn-based play -- a world without a `TurnState` is real-time.
class RealtimeOrderSystem extends System {
  RealtimeOrderSystem({required this.fields, this.attackRange = 1, this.autoEngage = true});

  final FlowFieldCache fields;

  /// Attack reach for units without an `AttackProfile`.
  final int attackRange;

  /// Whether a unit with nothing to do - or boxed in on its way somewhere - hits
  /// the nearest visible enemy in reach on its own. Without it a column of units
  /// jammed against each other, each ordered at a distant target, stand there
  /// being shot (found in the battle test); with it, idle defenders also fire back,
  /// as in every RTS.
  final bool autoEngage;

  @override
  String get name => 'realtimeOrders';

  @override
  void update(World world, double dt) {
    final queues = world.storeOf<OrderQueue>();
    final stats = world.storeOf<RealtimeStats>();
    // Snapshot the ids first - resolving an attack can destroy entities mid-loop -
    // and process them in id order. A ComponentStore's dense order depends on its
    // add/remove history, so a world rebuilt from a snapshot iterates differently
    // from the original; ordering by id is what keeps rollback and replay
    // bit-identical (who moves first decides who gets a contested cell).
    final ids = [for (var i = 0; i < queues.length; i++) queues.entityAt(i)]..sort();
    for (final entity in ids) {
      if (!world.entities.isAlive(entity)) continue;
      final s = stats.get(entity);
      final queue = queues.get(entity);
      if (s == null || queue == null) continue;
      s.cooldown = s.cooldown > dt ? s.cooldown - dt : 0;
      if (queue.orders.isEmpty) {
        s.moveProgress = 0;
        if (autoEngage) _engageNearest(world, entity, s);
        continue;
      }
      final order = queue.orders.first;
      final result = switch (order) {
        MoveOrder() => _move(world, entity, s, order, dt),
        AttackOrder() => _attack(world, entity, s, order, dt),
        _ => _fail(world, entity, order, OrderFailure.invalidTarget),
      };
      if (result != _Result.running && queue.orders.isNotEmpty && identical(queue.orders.first, order)) {
        queue.orders.removeAt(0);
        s.moveProgress = 0;
      }
    }
  }

  _Result _move(World world, EntityId entity, RealtimeStats s, MoveOrder order, double dt) {
    final grid = world.storeOf<GridPosition>();
    final pos = grid.get(entity);
    if (pos == null) return _fail(world, entity, order, OrderFailure.invalidTarget);
    if (pos.col == order.col && pos.row == order.row) return _Result.done;
    final field = fields.fieldFor(order.col, order.row);
    if (!field.reaches(pos.col, pos.row)) return _fail(world, entity, order, OrderFailure.blocked);
    final boxedIn =
        _advance(world, entity, s, field, dt, stopWhen: (p) => p.col == order.col && p.row == order.row);
    if (boxedIn && autoEngage) _engageNearest(world, entity, s);
    return pos.col == order.col && pos.row == order.row ? _Result.done : _Result.running;
  }

  _Result _attack(World world, EntityId entity, RealtimeStats s, AttackOrder order, double dt) {
    if (!world.entities.isAlive(order.target)) return _Result.done;
    final grid = world.storeOf<GridPosition>();
    final teams = world.storeOf<Team>();
    final me = grid.get(entity);
    final target = grid.get(order.target);
    final myTeam = teams.get(entity)?.id;
    if (me == null || target == null || myTeam == null || teams.get(order.target)?.id == myTeam) {
      return _fail(world, entity, order, OrderFailure.invalidTarget);
    }
    if (!canSee(world, myTeam, order.target)) {
      return _fail(world, entity, order, OrderFailure.invalidTarget);
    }
    final reach = world.storeOf<AttackProfile>().get(entity)?.range ?? attackRange;
    if (me.chebyshev(target) <= reach) {
      if (s.cooldown <= 0) {
        resolveAttack(world, entity, order.target);
        s.cooldown = s.attackInterval;
        if (!world.entities.isAlive(order.target)) return _Result.done;
      }
      return _Result.running;
    }
    final field = fields.fieldFor(target.col, target.row);
    if (!field.reaches(me.col, me.row)) return _fail(world, entity, order, OrderFailure.blocked);
    final boxedIn = _advance(world, entity, s, field, dt,
        ignore: order.target, stopWhen: (p) => p.chebyshev(target) <= reach);
    if (boxedIn && autoEngage) _engageNearest(world, entity, s);
    return _Result.running;
  }

  /// Hits the nearest visible enemy within reach if the unit's cooldown allows.
  /// Ties break by lowest entity id.
  void _engageNearest(World world, EntityId entity, RealtimeStats s) {
    if (s.cooldown > 0) return;
    final grid = world.storeOf<GridPosition>();
    final teams = world.storeOf<Team>();
    final me = grid.get(entity);
    final myTeam = teams.get(entity)?.id;
    if (me == null || myTeam == null || !world.storeOf<UnitStats>().has(entity)) return;
    final reach = world.storeOf<AttackProfile>().get(entity)?.range ?? attackRange;
    EntityId? best;
    var bestDist = 1 << 30;
    for (var i = 0; i < grid.length; i++) {
      final other = grid.entityAt(i);
      final otherTeam = teams.get(other)?.id;
      if (otherTeam == null || otherTeam == myTeam || !world.storeOf<UnitStats>().has(other)) continue;
      final d = me.chebyshev(grid.denseAt(i));
      // Nearest wins; equal distances go to the lower id, not whichever the store
      // happens to list first (see update()).
      if (d > reach || d > bestDist || (d == bestDist && other > best!) || !canSee(world, myTeam, other)) {
        continue;
      }
      best = other;
      bestDist = d;
    }
    if (best == null) return;
    resolveAttack(world, entity, best);
    s.cooldown = s.attackInterval;
  }

  /// Walks up to the steps [dt] earns. Returns true if the unit wanted to step
  /// but every improving cell was occupied (it is boxed in).
  bool _advance(
    World world,
    EntityId entity,
    RealtimeStats s,
    FlowField field,
    double dt, {
    EntityId? ignore,
    required bool Function(GridPosition) stopWhen,
  }) {
    final grid = world.storeOf<GridPosition>();
    final pos = grid.get(entity)!;
    final blocked = occupiedBy(grid, entity, ignore: ignore);
    s.moveProgress += s.speed * dt;
    // The epsilon makes exact multiples count: thirty 0.1s sum to 2.9999999999999996,
    // and a unit shouldn't be a whole cell short because of float rounding.
    while (s.moveProgress >= 1 - 1e-9) {
      final step = field.nextStep(pos, blocked: blocked);
      if (step == null) {
        // Boxed in by other units: wait with a full step banked, rather than
        // accumulating unbounded progress to burst forward later.
        s.moveProgress = 1;
        return true;
      }
      pos.col = step.col;
      pos.row = step.row;
      s.moveProgress = s.moveProgress - 1 < 0 ? 0 : s.moveProgress - 1;
      world.events.emit(MovedEvent(entity, pos.col, pos.row));
      if (stopWhen(pos)) {
        s.moveProgress = 0;
        return false;
      }
    }
    return false;
  }

  _Result _fail(World world, EntityId entity, Order order, OrderFailure why) {
    world.events.emit(OrderFailedEvent(entity, order, why));
    return _Result.failed;
  }
}

enum _Result { running, done, failed }

/// Declares the last team with units standing the winner (real-time's version of
/// `WinConditionSystem`, which needs a turn clock). Emits one `VictoryEvent` and
/// then goes quiet.
///
/// A team is only judged after it has been seen with units, so a team that never
/// had any doesn't hand the game to someone on tick one.
class LastTeamStandingSystem extends System {
  /// The winning team, or null while the match is undecided.
  String? winner;

  final Set<String> _seen = {};

  @override
  String get name => 'lastTeamStanding';

  @override
  void update(World world, double dt) {
    if (winner != null) return;
    final teams = world.storeOf<Team>();
    final stats = world.storeOf<UnitStats>();
    final alive = <String>{};
    for (var i = 0; i < teams.length; i++) {
      if (stats.has(teams.entityAt(i))) alive.add(teams.denseAt(i).id);
    }
    _seen.addAll(alive);
    if (_seen.length > 1 && alive.length == 1) {
      winner = alive.single;
      world.events.emit(VictoryEvent(winner!));
    }
  }
}

/// A real-time unit's `RealtimeStats` plus everything `RealtimeOrderSystem`
/// needs, in one call -- the real-time counterpart of the turn-based spawn helper.
EntityId spawnRealtimeUnit(
  World world, {
  required String team,
  required int col,
  required int row,
  double speed = 2,
  double attackInterval = 1,
  int maxHp = 10,
  int attack = 3,
  int defense = 0,
}) {
  final id = world.spawn();
  world.storeOf<Team>().set(id, Team(team));
  world.storeOf<GridPosition>().set(id, GridPosition(col, row));
  world.storeOf<RealtimeStats>().set(id, RealtimeStats(speed: speed, attackInterval: attackInterval));
  world.storeOf<UnitStats>().set(id, UnitStats(maxHp: maxHp, attack: attack, defense: defense));
  return id;
}
