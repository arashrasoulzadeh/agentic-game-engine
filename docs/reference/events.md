# Events reference

Events are plain Dart objects delivered through `world.events`.

```dart
world.events.on<UnitDamagedEvent>((e) => print('${e.target} took ${e.amount}'));
world.events.emit(MyEvent());      // queued; delivered at the end of the step
```

- Delivery happens in `World.step`'s final `flush()`, after every system ran.
- A handler may emit more events; they're delivered in the **same** flush
  (up to 20 rounds, a guard against handler cycles).
- Handlers are keyed by exact runtime type — subscribe to the concrete class.

## engine_core — general

| Event | Fields | Emitted by |
|---|---|---|
| `CollisionEvent` | `a`, `b` | `CollisionSystem` |
| `TriggerEvent` | `triggerId`, `zone`, `other`, `data` | `installTriggerZones` |
| `TweenCompleteEvent` | `entity` | `TweenSystem` |
| `CinematicCompleteEvent` | — | `CinematicSystem` |

## engine_core — turn-based

| Event | Fields | Emitted by |
|---|---|---|
| `TurnStartedEvent` | `team`, `round` | `startTurnBasedGame`, `endTurn` |
| `TurnEndedEvent` | `team`, `round` | `endTurn` |
| `MovedEvent` | `entity`, `col`, `row` | `OrderSystem` (per step) |
| `AttackResolvedEvent` | `attacker`, `target` | `OrderSystem` |
| `UnitDamagedEvent` | `attacker`, `target`, `amount` | `installCombat` |
| `UnitDefeatedEvent` | `unit`, `team` | `installCombat` (just before destroy) |
| `OrderFailedEvent` | `entity`, `order`, `reason` | `OrderSystem` |
| `VictoryEvent` | `team` | `WinConditionSystem` |
| `StatusAppliedEvent` | `entity`, `id` | `applyStatus` |
| `StatusExpiredEvent` | `entity`, `id` | turn clock (`tickStatusEffects`) |

`OrderFailure` is one of `blocked`, `outOfRange`, `invalidTarget`.

## engine_platformer

| Event | Fields | Emitted by |
|---|---|---|
| `DamageEvent` | `entity`, `amount`, `source?` | `damageEntity` |
| `BlockedEvent` | `entity`, `originalDamage`, `stabilityLost`, `source?` | guard logic |
| `GuardBreakEvent` | `entity`, `source?` | guard logic |
| `DeathEvent` | `entity` | `damageEntity` |
| `MeleeHitEvent` | `attacker`, `target`, `damage` | melee attacks |
| `ParrySuccessEvent` | `defender`, `attacker` | `ParrySystem` |
| `ItemCollectedEvent` | `holder`, `itemId`, `amount` | `collectItem` |
| `BossPhaseChangedEvent` | `entity`, `patternId`, `phaseIndex` | `BossPhaseSystem` |
| `EnemyTelegraphEvent` | `enemy`, `previousState`, `telegraphDuration` | `EnemyCombatBehavior` |
| `EnemyAttackEvent` | `enemy`, `attackDuration` | `EnemyCombatBehavior` |

## Patterns

**Don't mutate the world inside a handler for something you're iterating.**
Handlers run after the systems, so it is safe to destroy entities there (this
is what `installCombat` does when a unit dies).

**Prefer events over polling.** A HUD that listens for `UnitDamagedEvent`
updates once per hit instead of scanning every unit every frame.
