# Remaining work

The single source of truth for what is left. Only open work lives here; delete items once shipped —
what shipped is recorded in [CHANGELOG.md](CHANGELOG.md); reasoning lives
in git history. Add newly discovered work here rather than in comments or
side files.

Related (not task lists):
- [docs/studio/design.md](docs/studio/design.md) — studio PRD / design / delivered phases
- [docs/concepts/turn-based-strategy.md](docs/concepts/turn-based-strategy.md)
- [engine_mcp.md](engine_mcp.md) — agent API (phases 0–7 shipped; add ops via
  `zarvan_core` groups + `gen_api_docs.dart`)

Per-area lists live next to what they track: studio in
[docs/studio/studio.md](docs/studio/studio.md), and the sample games in
`mobarez/mobarez_todo.md` and `zahaak/zahaak_todo.md` (both folders are gitignored,
so those files exist only on the owner's machine).

Sections: [Release](#release) ·
[Wanted: engine gaps](#wanted-engine-gaps) ·
[Wanted: idle gaps](#wanted-idle-gaps)

## Release

- [ ] After the release exists, tell downstream projects `World.storeOf` is gone
      (see [docs/migrating-from-storeof.md](docs/migrating-from-storeof.md)); it was removed
      before the tag at the owner's request.
- [ ] Cut the first public release (the local `v0.1.0` tag is 600+ commits stale, retag at `main`), decide tag/`ref`
      policy for generated projects, publish packages to pub.dev (drops the
      self-referencing git-dep constraint), then swap README badges to
      pub.dev version badges. Checklist: [docs/engine-releasing.md](docs/engine-releasing.md).

## Wanted: engine gaps

Ten things a general 2D engine needed and did not have were checked against the source and built (time scale and
hit-stop, pooling, spawners, camera rig, joints, developer console, post-processing and shader effects, screen-reader
semantics, level mechanics, UI toolkit models); see the changelog. One follow-up remains. Tick items off as they
ship, with a test and docs.

- [ ] **UI toolkit: Flutter widgets for the new models.** `layoutStack`, `anchorRect`, `ScrollListModel` and
      `TextInputModel` exist as pure models; scenes still need widgets that render and drive them.

## Wanted: idle gaps

What `zarvan_idle` and the wave-combat layer still lack for a full idle game, most important first:

- [ ] **Automation in wave combat.** `AutoBuyer` exists in core, but the wave scene still needs taps to buy upgrades,
      cast skills, retry and ascend. Add auto-buy, auto-cast, auto-retry and auto-ascend toggles (generic, config-driven).
- [ ] **Flutter widgets for the UI toolkit models** (see above): scrolling lists, tabs, popups and tooltips for shops,
      inventories and skill trees.
- [ ] **Meta-progression beyond one prestige.** A talent or skill tree bought with prestige currency, achievements with
      permanent bonuses, daily quests and login streaks.
- [ ] **Many heroes.** Party or companions, summon or collection, and a gear inventory screen with rarity and merging
      (loot drops exist; browsing and comparing gear does not).
- [ ] **Offline that includes combat.** Offline pays coins only; simulate waves cleared and loot, and show a
      "welcome back" breakdown.
- [ ] Big-number formatting (1.2K, 3.4aa) and values beyond double range; a multi-currency HUD.
- [ ] A rewarded-boost extension point (for example "double offline earnings") that works with any ads or purchase SDK.
- [ ] Live events: remote config or an event calendar, server-time anti-cheat, leaderboards.
- [ ] A visual balance-curve viewer on top of the existing simulator.
- [ ] **Benchmark post-processing on real devices** (an Android phone and an iPhone, profile builds) and add the figures
      to `docs/data/postfx-benchmark.json` and the [post-processing page](docs/concepts/post-processing.md); all current
      numbers are web-only.
- [ ] **Snapshot-free shader path.** Run the same `post_fx` shader through `ImageFilter.shader` on Impeller platforms, so
      the per-frame snapshot (the whole cost, about 6 ms per megapixel on the web) disappears on iOS and Android.
