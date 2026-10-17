# TURNBASE.md

Plan and progress for turn-based strategy support. Realtime (RTS) is a
later phase that reuses most of this; see the end.

## Packaging

Genre-general **data** (teams, turn clock, action points, orders) and
the turn logic that is not tied to a genre live in `engine_core`
(`lib/src/turn/`). Strategy-specific rules (grid movement costs,
combat, fog of war) go in a new `engine_strategy` package depending on
`engine_core` and `engine_flutter`, mirroring `engine_platformer`.
The package DAG is unchanged.

## Phases

- [x] **1. Turn clock** — `Team`, `ActionPoints`, `TurnState`,
  `TurnStartedEvent`/`TurnEndedEvent`, `startTurnBasedGame`, `endTurn`,
  `trySpendActionPoints` (single out-of-turn gate), and `TurnSystem`
  (optional auto-end per team). Registered in `registerCoreComponents`,
  schemas in `engine_schema`. Tests: `engine_core/test/turn_system_test.dart`.
- [x] **2. Orders** — `OrderQueue` component + `MoveOrder`/`AttackOrder`
  data, an executor system that spends AP through
  `trySpendActionPoints`. Orders are JSON so an agent can submit them.
- [x] **3. Grid movement** — 8-directional A* with terrain costs and
  unit blocking (the current `findPath` is 4-directional and
  platformer-flavored); reachable-tiles query for move-range overlays.
  `GridNavigator` (`findPath`, `reachable`, `fromTileMap`) +
  `OrderSystem.withNavigator`; no diagonal corner-cutting past walls.
  Tests: `grid_navigation_test.dart`.
- [x] **4. Selection and input** — single/multi select component,
  tap-to-select/tap-to-order in `engine_flutter`, selection rings.
  Core: `Selected`, `selectAtCell`, `selectInBox`, `commandSelected`,
  `GridToWorldSystem`. Flutter: `GridTapController` (one-line
  `Scene.handleTap`), `SelectionMarkerSystem` (a world-space `HudBar`
  under each selected unit, reusing the existing renderer). Tests:
  `selection_test.dart`, `grid_selection_test.dart`.
- [x] **5. Combat and win conditions** — damage reuse (`damageEntity`),
  team elimination skipping in turn order, victory event.
  `UnitStats` (own component: the platformer `Health` is later in the
  DAG), `installCombat`, `WinConditionSystem`, `TurnState.eliminated`/
  `winner`; no friendly fire; turns/orders freeze after victory.
  Tests: `combat_test.dart`.
- [x] **6. Fog of war** — per-team visibility built on the existing
  line-of-sight/raycast code.
  `Vision`, `FogOfWar` (visible + explored per team, as world state so
  agents see exactly what a team sees), `VisionSystem` with a
  `blocksSight` predicate (separate from movement: you see across a
  lake), `canSee`; attacking an unseen enemy fails. Tests:
  `fog_of_war_test.dart`.
- [x] **7. `engine_strategy` package + `game_agent create` template.**
  `installStrategySystems` (documented order), `spawnStrategyUnit`,
  `game_agent create --template strategy_game` (verified: generated
  project analyzes clean and boots), `upgrade` repins `engine_strategy`.
  `OrderSystem.approachTargets` added when the end-to-end test showed a
  tap on a distant enemy failed `outOfRange` instead of walking over.
- [x] **8. AI turn driver** — a `Behavior` running a whole team's turn
  through the same order API a human uses.
  `TurnAI`, `AggressiveAI` (attacks the nearest enemy its team can
  *see*, so fog binds the AI too), `AITurnSystem` (plans once per
  round, ends the turn when no queued order can still progress; must
  register after `OrderSystem`), `installStrategySystems(aiTeams:)`;
  the template's blue team is now an AI. Tests: `ai_turn_test.dart`.

All eight phases are complete. Remaining ideas (not scheduled):
stronger AI (move-toward when nothing is visible, focus fire), terrain
rendering for tile maps in the template, and the realtime follow-up below.

## Realtime follow-up

Needs a fixed-timestep accumulator (lockstep determinism), flow-field
pathfinding for many units, and the order/selection layers from phases
2–4 unchanged.

## Decisions

- Teams are string ids, not an enum, so level data and agents can add
  sides without engine changes.
- Action points refill at the *start* of a team's turn, so the budget
  visible during an opponent's turn is the one the team will have.
- Turn rules are gated in one function (`trySpendActionPoints`) rather
  than re-checked by each action type.
