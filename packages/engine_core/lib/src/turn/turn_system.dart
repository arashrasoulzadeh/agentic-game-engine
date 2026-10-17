import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'status.dart';
import 'turn_components.dart';

/// Creates the turn-manager entity and starts the first team's turn
/// (refilling its action points and emitting [TurnStartedEvent]).
/// Requires `turnState`, `team` and `actionPoints` to be registered.
EntityId startTurnBasedGame(World world, List<String> teamOrder) {
  if (teamOrder.isEmpty) {
    throw ArgumentError('teamOrder must contain at least one team');
  }
  final manager = world.spawn();
  final state = TurnState(List<String>.from(teamOrder));
  world.storeOf<TurnState>().set(manager, state);
  _beginTurn(world, state);
  return manager;
}

/// The single [TurnState] in [world], or null before
/// [startTurnBasedGame]. A world has at most one turn clock.
TurnState? turnStateOf(World world) {
  final store = world.storeOf<TurnState>();
  return store.length == 0 ? null : store.denseAt(0);
}

/// Ends the active team's turn and starts the next. Returns false if
/// there is no turn clock.
bool endTurn(World world) {
  final state = turnStateOf(world);
  if (state == null || state.winner != null) return false;
  if (state.eliminated.length >= state.order.length) return false;
  world.events.emit(TurnEndedEvent(state.activeTeam, state.round));
  do {
    state.activeIndex++;
    if (state.activeIndex >= state.order.length) {
      state.activeIndex = 0;
      state.round++;
    }
  } while (state.eliminated.contains(state.activeTeam));
  _beginTurn(world, state);
  return true;
}

/// Spends [cost] from [entity]'s action points. Fails (returns false,
/// changes nothing) if it is not that entity's team's turn, it has no
/// budget, or the budget is too small -- the one gate every acting
/// system and agent goes through, so "can't act out of turn" is
/// enforced in one place instead of re-checked per action type.
bool trySpendActionPoints(World world, EntityId entity, int cost) {
  final state = turnStateOf(world);
  final team = world.storeOf<Team>().get(entity);
  final ap = world.storeOf<ActionPoints>().get(entity);
  if (state == null || state.winner != null || team == null || ap == null) return false;
  if (team.id != state.activeTeam || cost < 0 || ap.current < cost) return false;
  ap.current -= cost;
  return true;
}

void _beginTurn(World world, TurnState state) {
  final teams = world.storeOf<Team>();
  final points = world.storeOf<ActionPoints>();
  for (var i = 0; i < teams.length; i++) {
    if (teams.denseAt(i).id != state.activeTeam) continue;
    points.get(teams.entityAt(i))?.refill();
  }
  tickStatusEffects(world, state.activeTeam);
  world.events.emit(TurnStartedEvent(state.activeTeam, state.round));
}

/// Optionally ends the turn automatically once every entity on the
/// active team has spent all its action points. Off-by-default behavior
/// belongs to the game: a human player usually wants an explicit
/// "End turn" button, an AI-driven team usually wants this.
class TurnSystem extends System {
  /// Teams whose turn ends by itself when out of points.
  final Set<String> autoEndTeams;

  TurnSystem({this.autoEndTeams = const {}});

  @override
  String get name => 'turn';

  @override
  void update(World world, double dt) {
    final state = turnStateOf(world);
    if (state == null || !autoEndTeams.contains(state.activeTeam)) return;
    final teams = world.storeOf<Team>();
    final points = world.storeOf<ActionPoints>();
    var anyActor = false;
    for (var i = 0; i < teams.length; i++) {
      if (teams.denseAt(i).id != state.activeTeam) continue;
      final ap = points.get(teams.entityAt(i));
      if (ap == null) continue;
      anyActor = true;
      if (ap.current > 0) return;
    }
    if (anyActor) endTurn(world);
  }
}
