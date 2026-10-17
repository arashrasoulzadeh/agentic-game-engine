import '../ecs/entity.dart';
import '../ecs/world.dart';
import 'combat.dart';
import 'order.dart';
import 'turn_components.dart';
import 'turn_system.dart';

/// A capture point on the grid. A team takes it by standing on it when that team's
/// turn begins; it stays theirs until another team does the same.
class Objective {
  /// A name for UI and tests ("flag", "bridge").
  final String id;
  final int col;
  final int row;

  /// The team holding it, or null while neutral.
  String? owner;

  Objective(this.id, this.col, this.row, {this.owner});

  Map<String, dynamic> toJson() => {'id': id, 'col': col, 'row': row, 'owner': owner};
  factory Objective.fromJson(Map<String, dynamic> json) => Objective(
        json['id'] as String,
        (json['col'] as num).toInt(),
        (json['row'] as num).toInt(),
        owner: json['owner'] as String?,
      );
}

/// Optional win-by-holding rule, kept as world state so it saves. A team that
/// owns *every* objective at the start of [holdTurnsToWin] of its consecutive
/// turns wins; losing one resets the count.
class ObjectiveRules {
  final int holdTurnsToWin;

  /// Consecutive qualifying turn starts per team.
  final Map<String, int> holds;

  ObjectiveRules({required this.holdTurnsToWin, Map<String, int>? holds}) : holds = holds ?? {};

  Map<String, dynamic> toJson() => {'holdTurnsToWin': holdTurnsToWin, 'holds': holds};
  factory ObjectiveRules.fromJson(Map<String, dynamic> json) => ObjectiveRules(
        holdTurnsToWin: (json['holdTurnsToWin'] as num).toInt(),
        holds: {for (final e in ((json['holds'] as Map?) ?? const {}).entries) e.key as String: (e.value as num).toInt()},
      );
}

/// Emitted when [team] takes [objective] ([previousOwner] is null if it was neutral).
class ObjectiveCapturedEvent {
  final EntityId objective;
  final String team;
  final String? previousOwner;
  ObjectiveCapturedEvent(this.objective, this.team, this.previousOwner);
}

/// The capture + hold-to-win step for [team]. The turn clock runs it
/// synchronously as each team's turn begins -- before any queued order moves a
/// unit off a point -- so there is nothing to install; it is exposed so scripted
/// scenarios and tests can also drive it directly.
///
/// A cell holds one unit, so "standing on it" is enough; there is no contested
/// state. With `ObjectiveRules` present it also checks hold-to-win.
void resolveObjectives(World world, String team) {
  final objectives = world.storeOf<Objective>();
  final grid = world.storeOf<GridPosition>();
  final teams = world.storeOf<Team>();
  for (var i = 0; i < objectives.length; i++) {
    final o = objectives.denseAt(i);
    if (o.owner == team) continue;
    for (var g = 0; g < grid.length; g++) {
      final p = grid.denseAt(g);
      if (p.col == o.col && p.row == o.row && teams.get(grid.entityAt(g))?.id == team) {
        final previous = o.owner;
        o.owner = team;
        world.events.emit(ObjectiveCapturedEvent(objectives.entityAt(i), team, previous));
        break;
      }
    }
  }

  final rules = world.storeOf<ObjectiveRules>();
  if (rules.length == 0 || objectives.length == 0) return;
  final r = rules.denseAt(0);
  var holdsAll = true;
  for (var i = 0; i < objectives.length; i++) {
    if (objectives.denseAt(i).owner != team) holdsAll = false;
  }
  r.holds[team] = holdsAll ? (r.holds[team] ?? 0) + 1 : 0;
  final turn = turnStateOf(world);
  if (turn != null && turn.winner == null && r.holds[team]! >= r.holdTurnsToWin) {
    turn.winner = team;
    world.events.emit(VictoryEvent(team));
  }
}

/// Objectives not owned by [team] (neutral or enemy-held), as `(entity, objective)`.
List<(EntityId, Objective)> objectivesToTake(World world, String team) {
  final store = world.storeOf<Objective>();
  return [
    for (var i = 0; i < store.length; i++)
      if (store.denseAt(i).owner != team) (store.entityAt(i), store.denseAt(i)),
  ];
}
