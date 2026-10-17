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
- [ ] **4. Selection and input** — single/multi select component,
  tap-to-select/tap-to-order in `engine_flutter`, selection rings.
- [ ] **5. Combat and win conditions** — damage reuse (`damageEntity`),
  team elimination skipping in turn order, victory event.
- [ ] **6. Fog of war** — per-team visibility built on the existing
  line-of-sight/raycast code.
- [ ] **7. `engine_strategy` package + `game_agent create` template.**
- [ ] **8. AI turn driver** — a `Behavior` running a whole team's turn
  through the same order API a human uses.

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
