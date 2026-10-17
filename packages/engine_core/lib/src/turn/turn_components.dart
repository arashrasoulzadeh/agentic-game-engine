/// Which side an entity belongs to. A plain string id (not an enum) so
/// level data and agents can introduce teams without engine changes;
/// `TurnState.order` is what gives the ids their sequence.
class Team {
  String id;
  Team(this.id);

  Map<String, dynamic> toJson() => {'id': id};
  factory Team.fromJson(Map<String, dynamic> json) => Team(json['id'] as String);
}

/// Per-turn action budget. Kept separate from `Team` so non-acting
/// entities (props, buildings) can belong to a side without a budget,
/// and so a game can spend points on anything -- moving, attacking,
/// building -- without the engine knowing which.
class ActionPoints {
  int current;
  int max;

  ActionPoints(this.max, {int? current}) : current = current ?? max;

  /// Refilled when the owning team's turn starts, not when it ends:
  /// the budget an agent reads during the *opponent's* turn is then the
  /// one it will actually have, which is what planning needs.
  void refill() => current = max;

  Map<String, dynamic> toJson() => {'current': current, 'max': max};
  factory ActionPoints.fromJson(Map<String, dynamic> json) {
    final max = (json['max'] as num).toInt();
    return ActionPoints(max, current: (json['current'] as num?)?.toInt() ?? max);
  }
}

/// The turn clock, stored as a component on one "manager" entity so it
/// rides along in `World.toJson()`/saves/replays like all other state
/// rather than living in a hidden system field.
class TurnState {
  /// Team ids in play order. Fixed at setup; a team that is eliminated
  /// is skipped by game logic ending its turn, not by mutating this.
  List<String> order;
  int activeIndex;

  /// 1-based; increments each time play wraps back to the first team.
  int round;

  TurnState(this.order, {this.activeIndex = 0, this.round = 1});

  String get activeTeam => order[activeIndex];

  Map<String, dynamic> toJson() => {
        'order': order,
        'activeIndex': activeIndex,
        'round': round,
      };
  factory TurnState.fromJson(Map<String, dynamic> json) => TurnState(
        List<String>.from(json['order'] as List),
        activeIndex: (json['activeIndex'] as num?)?.toInt() ?? 0,
        round: (json['round'] as num?)?.toInt() ?? 1,
      );
}

/// Emitted when [team] becomes active, after its action points refill.
class TurnStartedEvent {
  final String team;
  final int round;
  TurnStartedEvent(this.team, this.round);
}

/// Emitted when [team]'s turn ends, before the next team starts.
class TurnEndedEvent {
  final String team;
  final int round;
  TurnEndedEvent(this.team, this.round);
}
