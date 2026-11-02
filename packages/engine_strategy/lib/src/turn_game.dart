import 'package:engine_core/engine_core.dart';

import 'spawn_helpers.dart';
import 'strategy_systems.dart';

/// One object for a turn-based game: it installs the systems, spawns units,
/// starts the clock and turns "move that unit there" into one call. Everything
/// it does is a thin call into the pieces it wraps (`installStrategySystems`,
/// `spawnStrategyUnit`, `startTurnBasedGame`, `submitOrder`, `endTurn`,
/// `selectAtCell`, `commandSelected`), so a game can drop down to them whenever
/// the facade is too small.
///
/// ```dart
/// final game = TurnGame.setup(world,
///     navigator: GridNavigator(cols: 8, rows: 8, terrainCost: (_, _) => 1),
///     cellSize: 32,
///     teams: ['red', 'blue'],
///     aiTeams: {'blue': myAi});
/// final knight = game.spawnUnit('red', 1, 1);
/// game.spawnUnit('blue', 5, 1);
/// game.start();
/// game.moveTo(knight, 3, 1);
/// world.step(1 / 60);        // orders run inside the world's step
/// game.endTurn();
/// ```
class TurnGame {
  /// The world the game runs in.
  final World world;

  /// Teams in play order.
  final List<String> teams;

  /// Pixels per grid cell.
  final double cellSize;

  EntityId? _clock;

  TurnGame._(this.world, this.teams, this.cellSize);

  /// Installs the strategy systems on [world] (see [installStrategySystems],
  /// whose other options pass straight through) and returns the game. Spawn
  /// units with [spawnUnit], then call [start].
  factory TurnGame.setup(
    World world, {
    required GridNavigator navigator,
    required double cellSize,
    required List<String> teams,
    Set<String> autoEndTeams = const {},
    Map<String, TurnAI> aiTeams = const {},
    int attackRange = 1,
    int attackCost = 1,
    int defendBonus = 2,
    bool fog = false,
    bool selectionMarkers = true,
  }) {
    if (teams.isEmpty) throw ArgumentError('teams must not be empty');
    installStrategySystems(
      world,
      navigator: navigator,
      cellSize: cellSize,
      autoEndTeams: autoEndTeams,
      aiTeams: aiTeams,
      attackRange: attackRange,
      attackCost: attackCost,
      defendBonus: defendBonus,
      fog: fog,
      selectionMarkers: selectionMarkers,
    );
    return TurnGame._(world, List.unmodifiable(teams), cellSize);
  }

  /// Spawns a unit of [team] at ([col], [row]); see [spawnStrategyUnit] for the
  /// stats. Must happen before [start], which refills the first team's points.
  EntityId spawnUnit(
    String team,
    int col,
    int row, {
    int maxHp = 10,
    int attack = 3,
    int defense = 0,
    int actionPoints = 3,
    int? attackRange,
  }) {
    if (!teams.contains(team)) {
      throw ArgumentError.value(team, 'team', 'not one of $teams');
    }
    return spawnStrategyUnit(
      world,
      team: team,
      col: col,
      row: row,
      cellSize: cellSize,
      maxHp: maxHp,
      attack: attack,
      defense: defense,
      actionPoints: actionPoints,
      attackRange: attackRange,
    );
  }

  /// Starts the turn clock with the first team. Throws if already started.
  void start() {
    if (_clock != null) throw StateError('TurnGame already started.');
    _clock = startTurnBasedGame(world, List.of(teams));
  }

  TurnState get _state {
    final s = turnStateOf(world);
    if (s == null) throw StateError('Call TurnGame.start() first.');
    return s;
  }

  /// The team whose turn it is.
  String get activeTeam => _state.activeTeam;

  /// 1-based round number.
  int get round => _state.round;

  /// The winning team once only one is left, else null.
  String? get winner => _state.winner;

  /// Ends the active team's turn. False when the game is over.
  bool endTurn() => _endTurn(world);

  /// Orders [unit] to walk to ([col], [row]). False when it is not that unit's
  /// team's turn (see [submitOrder]).
  bool moveTo(EntityId unit, int col, int row) =>
      submitOrder(world, unit, MoveOrder(col, row));

  /// Orders [unit] to attack [target].
  bool attack(EntityId unit, EntityId target) =>
      submitOrder(world, unit, AttackOrder(target));

  /// Orders [unit] to defend for the enemy's turn.
  bool defend(EntityId unit) => submitOrder(world, unit, const DefendOrder());

  /// Selects the active team's unit at ([col], [row]); null if none there.
  EntityId? select(int col, int row, {bool additive = false}) =>
      selectAtCell(world, col, row, additive: additive);

  /// Selects every listed unit of the active team that can be selected;
  /// returns how many were.
  int selectAll(Iterable<EntityId> units) {
    clearSelection(world);
    var n = 0;
    for (final u in units) {
      final cell = world.componentsOf<GridPosition>().get(u);
      if (cell != null &&
          selectAtCell(world, cell.col, cell.row, additive: true) != null) {
        n++;
      }
    }
    return n;
  }

  /// Orders every selected unit toward ([col], [row]): attack if an enemy is
  /// there, else move. Returns how many orders were accepted.
  int commandSelected(int col, int row) => _commandSelected(world, col, row);

  /// Calls [callback] with the team name whenever a turn begins.
  Subscription onTurnStarted(void Function(String team, int round) callback) =>
      world.on<TurnStartedEvent>((e) => callback(e.team, e.round));

  /// Calls [callback] with the team name whenever a turn ends.
  Subscription onTurnEnded(void Function(String team, int round) callback) =>
      world.on<TurnEndedEvent>((e) => callback(e.team, e.round));
}

// The engine_core functions share names with the facade's methods, so they are
// reached through these aliases from inside the class.
bool _endTurn(World world) => endTurn(world);
int _commandSelected(World world, int col, int row) =>
    commandSelected(world, col, row);
