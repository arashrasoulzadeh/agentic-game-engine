import '../../../engine_core.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';
import 'level_ops.dart';

/// Static description of the turn-based rules an agent (or `strategy.simulate_turns`) uses.
Map<String, Object?> strategyRulesDescription() => {
  'genre': 'turn-based strategy',
  'components': {
    'team': 'Side id (string). Units without one are ignored by the turn clock.',
    'gridPosition': 'Integer cell `{col, row}` — strategy movement/combat use this, not `position`.',
    'actionPoints': '`{max, current?}`; refilled when the unit\'s team begins a turn.',
    'unitStats': '`{maxHp, hp?, attack, defense}` — combat and win detection.',
    'attackProfile': 'Optional `{range, cost}` for ranged / expensive attacks.',
    'orderQueue': 'Queued intents; agents submit via `submitOrder` (move/attack/defend/overwatch).',
    'turnState': 'The turn clock (`order`, `activeIndex`, `round`, `eliminated`, `winner`).',
    'tileMap': 'Optional; when present `GridNavigator.fromTileMap` uses solid tiles as impassable.',
  },
  'orders': ['move', 'attack', 'defend', 'overwatch'],
  'systems': [
    'OrderSystem.withNavigator',
    'AITurnSystem',
    'TurnSystem',
    'WinConditionSystem',
    'installCombat',
  ],
  'combatDefaults': {
    'attackRange': 1,
    'attackCost': 1,
    'defendBonus': 2,
  },
  'ai': {
    'aggressive': 'Focus-fires the weakest in-range enemy; moves closer otherwise.',
    'tactical': 'Focus-fires, retreats when hurt, explores when nothing is seen (needs navigator).',
  },
  'levelShape':
      'Entities with team + gridPosition + actionPoints + unitStats; optional tileMap for terrain. '
      'If no turnState exists, simulate_turns starts one with teams in first-seen order.',
};

TurnAI _aiFor(String kind, GridNavigator nav) => switch (kind) {
  'tactical' => TacticalAI(navigator: nav),
  'aggressive' => AggressiveAI(),
  _ => throw OpError(
    ErrorCode.invalidParams,
    'Unknown ai "$kind".',
    hint: 'Choose aggressive or tactical.',
  ),
};

GridNavigator _navigator(World world) {
  final maps = world.storeOf<TileMap>();
  if (maps.length > 0) return GridNavigator.fromTileMap(maps.denseAt(0));
  var maxCol = 7, maxRow = 7;
  final grids = world.storeOf<GridPosition>();
  for (var i = 0; i < grids.length; i++) {
    final g = grids.denseAt(i);
    if (g.col > maxCol) maxCol = g.col;
    if (g.row > maxRow) maxRow = g.row;
  }
  return GridNavigator(
    cols: maxCol + 1,
    rows: maxRow + 1,
    terrainCost: (_, _) => 1,
  );
}

List<String> _teams(World world) {
  final seen = <String>{};
  final order = <String>[];
  final teams = world.storeOf<Team>();
  final stats = world.storeOf<UnitStats>();
  for (var i = 0; i < teams.length; i++) {
    final e = teams.entityAt(i);
    if (stats.get(e) == null) continue;
    final id = teams.denseAt(i).id;
    if (seen.add(id)) order.add(id);
  }
  return order;
}

void _recordEvents(World world, List<Map<String, Object?>> events) {
  world.events.on<TurnStartedEvent>(
    (e) => events.add({
      'type': 'turnStarted',
      'team': e.team,
      'round': e.round,
    }),
  );
  world.events.on<TurnEndedEvent>(
    (e) => events.add({
      'type': 'turnEnded',
      'team': e.team,
      'round': e.round,
    }),
  );
  world.events.on<MovedEvent>(
    (e) => events.add({
      'type': 'moved',
      'entity': e.entity,
      'col': e.col,
      'row': e.row,
    }),
  );
  world.events.on<AttackResolvedEvent>(
    (e) => events.add({
      'type': 'attackResolved',
      'attacker': e.attacker,
      'target': e.target,
    }),
  );
  world.events.on<UnitDamagedEvent>(
    (e) => events.add({
      'type': 'unitDamaged',
      'attacker': e.attacker,
      'target': e.target,
      'amount': e.amount,
    }),
  );
  world.events.on<UnitDefeatedEvent>(
    (e) => events.add({
      'type': 'unitDefeated',
      'entity': e.unit,
      'team': e.team,
    }),
  );
  world.events.on<VictoryEvent>(
    (e) => events.add({'type': 'victory', 'winner': e.team}),
  );
  world.events.on<OrderFailedEvent>(
    (e) => events.add({
      'type': 'orderFailed',
      'entity': e.entity,
      'reason': e.reason.name,
    }),
  );
}

/// `strategy.*`: headless turn-based rules and AI simulation (pure core; no Flutter).
List<Operation> strategyOperations() => [
  Operation(
    name: 'strategy.rules',
    summary:
        'Describe the turn-based components, orders, systems and AI kinds the engine ships.',
    description:
        'A static catalogue for agents authoring strategy levels or calling `strategy.simulate_turns`. '
        'Nothing is loaded or run.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    handler: (ctx, a) => OpOutcome.data(strategyRulesDescription()),
  ),
  Operation(
    name: 'strategy.simulate_turns',
    summary:
        'Run a headless turn-based skirmish for a few team-turns and return the event log.',
    description:
        'Loads a level (`path` or inline `json`) with team/grid/AP/unitStats entities, wires '
        '`OrderSystem` + `AITurnSystem` + win/combat, and steps until `turns` team-turns have ended '
        '(or someone wins). `ai` selects AggressiveAI or TacticalAI for every team. Uses a TileMap '
        'navigator when the level has one; otherwise an open grid sized to the units. Deterministic '
        'for the same level + args. Nothing is written.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('path', ParamType.path, positional: true),
      Param('json', ParamType.json, cliFlag: 'inline-json'),
      Param(
        'turns',
        ParamType.integer,
        defaultValue: 1,
        description: 'How many team-turns (TurnEndedEvent) to run before stopping.',
      ),
      Param(
        'ai',
        ParamType.enumeration,
        options: ['aggressive', 'tactical'],
        defaultValue: 'aggressive',
      ),
    ],
    errors: {
      ErrorCode.validationFailed: 'The level does not load or has no combat units.',
    },
    handler: (ctx, a) {
      final turns = a['turns']! as int;
      if (turns < 1) {
        throw OpError(ErrorCode.invalidParams, '"turns" must be at least 1.');
      }
      final doc = parseLevel(levelText(ctx, a));
      final world = World(width: 1000, height: 1000);
      registerCoreComponents(world);
      try {
        Level.loadInto(world, doc.toJson());
      } on Object catch (e) {
        throw OpError(
          ErrorCode.validationFailed,
          'The level does not load ($e).',
        );
      }
      final teams = _teams(world);
      if (teams.length < 2) {
        throw OpError(
          ErrorCode.validationFailed,
          'Need at least two teams with unitStats; found ${teams.length}.',
        );
      }
      final nav = _navigator(world);
      final aiKind = a['ai']! as String;
      final controllers = {for (final t in teams) t: _aiFor(aiKind, nav)};
      world.addSystem(OrderSystem.withNavigator(nav));
      world.addSystem(AITurnSystem(controllers));
      world.addSystem(WinConditionSystem());
      installCombat(world);

      final events = <Map<String, Object?>>[];
      _recordEvents(world, events);
      // Subscribe before starting the clock so the first TurnStartedEvent is recorded.
      if (turnStateOf(world) == null) {
        startTurnBasedGame(world, teams);
      }

      var ended = 0;
      // AI plans one step, orders resolve on later steps; bound runaway games.
      final maxSteps = turns * teams.length * 64;
      for (var step = 0; step < maxSteps; step++) {
        final before = events.length;
        world.step(1 / 60);
        for (var i = before; i < events.length; i++) {
          if (events[i]['type'] == 'turnEnded') ended++;
        }
        final state = turnStateOf(world);
        if (state?.winner != null || ended >= turns) break;
      }

      final state = turnStateOf(world);
      return OpOutcome.data({
        'events': events,
        'winner': state?.winner,
        'round': state?.round,
        'activeTeam': state?.activeTeam,
        'teams': teams,
        'turnsEnded': ended,
        'ai': aiKind,
      });
    },
    examples: const [
      Example('Two units duke it out for a few turns', {
        'json': {
          'entities': [
            {
              'name': 'red',
              'components': {
                'team': {'id': 'red'},
                'gridPosition': {'col': 0, 'row': 0},
                'actionPoints': {'max': 4},
                'unitStats': {'maxHp': 14, 'attack': 5},
              },
            },
            {
              'name': 'blue',
              'components': {
                'team': {'id': 'blue'},
                'gridPosition': {'col': 1, 'row': 0},
                'actionPoints': {'max': 4},
                'unitStats': {'maxHp': 10, 'attack': 3},
              },
            },
          ],
        },
        'turns': 4,
      }),
    ],
  ),
];
