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
| `PlaySoundEvent` | `audioKey`, `volume` | `DialogueRunner`, cinematic `PlaySoundStep`; played by `DialogueSfxSystem` |

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
| `OverwatchTriggeredEvent` | `watcher`, `target` | `OrderSystem` (on a watcher's shot) |
| `ObjectiveCapturedEvent` | `objective`, `team`, `previousOwner` | the turn clock (`resolveObjectives`) |
| `FlagPickedUpEvent` | `flag`, `carrier` | `onUnitMoved` |
| `FlagDroppedEvent` | `flag`, `formerCarrier` | `resolveAttack` (carrier killed) |
| `FlagCapturedEvent` | `flag`, `team`, `total` | `onUnitMoved` (on delivery) |
| `UnitProducedEvent` | `producer`, `unit` | `ProductionSystem` |
| `ProductionStalledEvent` | `producer`, `missing` | `ProductionSystem` (once per stall) |
| `StatusAppliedEvent` | `entity`, `id` | `applyStatus` |
| `StatusExpiredEvent` | `entity`, `id` | turn clock (`tickStatusEffects`) |
| `ProductionLockedEvent` | `producer`, `missing` | `ProductionSystem` (once per lock) |
| `ResourceDeliveredEvent` | `unit`, `team`, `resource`, `amount` | `GatherSystem` (haul handed to a depot) |
| `ResourceDepletedEvent` | `node` | `GatherSystem` (just before the node is destroyed) |
| `BuildingCompletedEvent` | `building` | `ConstructionSystem` |

`OrderFailure` is one of `blocked`, `outOfRange`, `invalidTarget`.

## engine_core — AI and analytics

| Type | Fields | Notes |
|---|---|---|
| `SoundEvent` | `x`, `y`, `loudness`, `tag?`, `data?` | A world event your game emits when something makes noise; `HearingSystem` delivers it to listeners (see `InvestigateBehavior`). |
| `AnalyticsEvent` | `name`, `payload`, `timestamp`, `userId?`, `sessionId?` | **Not** a `world.events` event: a record handed to analytics providers by `AnalyticsManager`. Listed because of its name. |

## engine_flutter

| Event | Fields | Emitted by |
|---|---|---|
| `AnimationFrameEvent` | `entity`, `clipName`, `type`, `data`, `frameIndex` | `AnimationSystem` (one per cue when playback enters a frame whose `frameEvents` list one; `installAnimationCueSystems` turns `shake` / `particle` / `sfx` cues into camera shake, particle bursts and sound) |
| `AnimationEvent` | `type`, `data` | **Not** a `world.events` event: the authored cue data in `AnimationClip.frameEvents` / `SpriteClip.frameEvents`. Listed because of its name. |

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

## engine_idle

| Event | Fields | Emitted by |
|---|---|---|
| `AchievementUnlockedEvent` | `id` | `checkAchievements` |
| `GoldenOfferedEvent` | `lifetime` | `GoldenEventSystem` |
| `ChallengeCompletedEvent` | `id` | `checkChallenges` |

## Patterns

**Don't mutate the world inside a handler for something you're iterating.**
Handlers run after the systems, so it is safe to destroy entities there (this
is what `installCombat` does when a unit dies).

**Prefer events over polling.** A HUD that listens for `UnitDamagedEvent`
updates once per hit instead of scanning every unit every frame.
