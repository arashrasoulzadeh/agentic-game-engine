# Recipe: write your own turn-based AI

A `TurnAI` plays one team's whole turn by calling `submitOrder` — the same
function a tap uses. That means it can't cheat: fog, turn order and action
points all apply to it.

```dart
/// Targets the visible enemy with the fewest hit points.
class FocusFireAI implements TurnAI {
  @override
  void playTurn(World world, String team) {
    final teams = world.storeOf<Team>();
    final stats = world.storeOf<UnitStats>();

    // 1. Pick a target among enemies this team can actually see.
    EntityId? weakest;
    for (var i = 0; i < teams.length; i++) {
      final e = teams.entityAt(i);
      if (teams.denseAt(i).id == team || !canSee(world, team, e)) continue;
      final hp = stats.get(e)?.hp;
      if (hp == null) continue;
      if (weakest == null || hp < stats.get(weakest)!.hp) weakest = e;
    }
    if (weakest == null) return;            // nothing in sight: hold position

    // 2. Everyone attacks it. Units walk into range automatically.
    for (var i = 0; i < teams.length; i++) {
      if (teams.denseAt(i).id != team) continue;
      submitOrder(world, teams.entityAt(i), AttackOrder(weakest));
    }
  }
}
```

Register it:

```dart
installStrategySystems(world, navigator: nav, cellSize: 48,
    aiTeams: {'blue': FocusFireAI()});
```

## How the turn ends

You don't call `endTurn`. `AITurnSystem` ends the turn once none of the team's
queued orders can still make progress (they're waiting for points that arrive
next turn). A unit that is out of points and has an order simply resumes next
round.

## Ideas to build from this

| Behaviour | Hint |
|---|---|
| Retreat when hurt | If `hp / maxHp < 0.3`, `MoveOrder` toward your side of the map instead of attacking. |
| Hold a choke point | `MoveOrder` to fixed cells, never `AttackOrder` unless an enemy is adjacent. |
| Explore | When nothing is visible, `MoveOrder` toward the nearest cell not in `fog.explored[team]`. |
| Different personalities per team | `aiTeams: {'blue': FocusFireAI(), 'green': AggressiveAI()}`. |

## Notes

- `playTurn` runs once per round per team. It can queue several orders per
  unit; they run in order.
- Clear a unit's old orders first (`world.storeOf<OrderQueue>().get(unit)?.orders.clear()`)
  if it may still hold one from last turn — `AggressiveAI` does this.
- To use an LLM, build the observation from `world.toJson()` and parse the
  reply with `Order.fromJson` — see [Tutorial 3](../tutorials/03-agent-driven-game.md).

*Verified by `doc_examples_test.dart` ("custom TurnAI").*
