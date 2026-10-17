import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'fog_of_war.dart';
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
