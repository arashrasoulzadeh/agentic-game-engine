# Idle games

!!! note "Work in progress"
    The engine can host an idle (incremental) game today, but the genre layer is being built. This page covers
    what exists; what is still to come is tracked in [`TODO_IDLE.md`](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/TODO_IDLE.md).

Samples are executed by `packages/engine_core/test/doc_examples_idle_test.dart`.

## Numbers that do not overflow

An incremental game's totals outgrow a 64-bit integer within hours, and a `double` stops at 1e308. `BigNumber`
stores `mantissa * 10^exponent`, so the range is effectively unbounded and arithmetic never overflows:

```dart
final a = BigNumber.parse('1.5e300');
final b = BigNumber.from(2000);
a * b;                     // 3e303
a + BigNumber.one;         // unchanged: a term 17 orders of magnitude smaller is lost, like a double
a.pow(2); a.sqrt(); a.log10(); a.floor();
a > b;                     // total order, also across signs and zero
```

- It keeps about **15 significant digits**. That is the right trade for an idle game and the wrong one for money.
- Division by zero, `NaN` and infinity throw instead of spreading.
- JSON is the string `"1.5e300"`; it round-trips exactly.
- Compare results of long arithmetic chains with `approxEquals`, not `==`.

## Showing them

```dart
formatBigNumber(BigNumber.from(1234567));                                  // 1.23M
formatBigNumber(BigNumber.parse('4.5e12'), style: NumberStyle.scientific); // 4.50e12
formatBigNumber(BigNumber.from(999999));                                   // 1.00M  (rounding carries)
```

Styles: `suffix` (`K M B T Qa Qi Sx Sp Oc No Dc`, then scientific), `scientific`, `engineering`. Numbers below 1000 print
plainly. `decimals` and `decimalSeparator` are configurable.

## Resources: `BigTreasury`

`BigTreasury` is the idle-scale counterpart of the strategy `Treasury`: named resources and per-second income as
`BigNumber`s.

```dart
final wallet = BigTreasury(
  amounts: {'coins': BigNumber.from(10)},
  incomePerSecond: {'coins': BigNumber.from(5)},
);
wallet.accrue(1.0);                                   // income is rate x time
wallet.spend({'coins': BigNumber.from(50000)});       // true, or false and nothing taken
```

`accrue` is correct for any step size: one six-hour step gives the same result as 21,600 one-second steps, which
is what makes offline catch-up cheap. It is a registered component (`bigTreasury`), so it saves with the world.

## Offline progress

```dart
final summary = OfflineProgress.catchUp(
  wallet,
  lastActiveAt: leftAt,       // save this when the app pauses
  now: DateTime.now(),        // pass the clock in; the engine never reads it itself
);
summary.gained;               // {coins: 54000} for the "while you were away" screen
summary.credit.capped;        // true if the absence hit the cap
```

`OfflineConfig` sets the **cap** (default 8 hours), the **efficiency** (fraction of normal income earned away) and
the **minimum** absence (default 30 s; anything shorter earns and shows nothing). A clock that moved *backwards*
grants nothing. `OfflineProgress.untilCap` tells you when the cap will be reached, for a reminder.

!!! warning "Constant rates only"
    Catch-up assumes your income rates stay the same while away. If your game has automation that spends money on
    upgrades (auto-buyers), simulate that in game code in a few large steps instead; the maths here cannot know it.
