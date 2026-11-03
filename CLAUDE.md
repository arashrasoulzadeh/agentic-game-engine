# CLAUDE.md

Guidance for Claude (or any AI agent) working in this repository.

## What this repo is

ZARVAN is an agent-native, simulation-first game engine built with Dart: a pure-Dart 2D game engine, built to be **AI-agent-friendly** as a
first-class design goal, not an afterthought: world state is
JSON-serializable data an agent can read/patch, content is authored as
data (not code), and a `Behavior`/`WorldView` sandbox lets an agent
drive an entity at runtime without any path to corrupting simulation
state. Flutter is used only as the cross-platform rendering/input/audio
shell — the actual engine (`zarvan_core`) has zero Flutter dependency.

**This repo is the engine library itself, not a game.** There is
deliberately no sample app checked into git — `test_game/` (a real,
playable sample platformer exercising every major engine feature) is
gitignored and exists only locally for manual verification. Never
un-gitignore it or commit a sample app to this repo; that decision was
made explicitly (see the "Remove root sample app" commit).

## Package map

| Package | What | Depends on |
|---|---|---|
| `packages/zarvan_core` | Genre-general ECS, `TileMap` data, content DSL, agent API. Pure Dart, no Flutter. | nothing engine-internal |
| `packages/zarvan_flutter` | Rendering, input, camera, audio, save/load. | `zarvan_core` |
| `packages/zarvan_platformer` | Platformer-genre gameplay: gravity, jump, tile/platform collision, spawn helpers, patrol/follow behaviors, movement animation. | `zarvan_core`, `zarvan_flutter` |
| `packages/zarvan_strategy` | Turn-based strategy assembly: `installStrategySystems`, `spawnStrategyUnit`. Rules/data live in `zarvan_core/lib/src/turn/`. | `zarvan_core`, `zarvan_flutter` |
| `packages/zarvan_idle` | Idle / incremental-game layer: widgets, `IdleController`, `IdleSession` (lifecycle/saving). The Flutter-free idle rules live in `zarvan_core` (`zarvan_core_idle.dart`) so the CLI can use them; see the idle section of `TODO.md`. | `zarvan_core`, `zarvan_flutter` |
| `packages/zarvan_api` | MCP server + HTTP/JSON-RPC API over the operation registry in `zarvan_core` (spec: `engine_mcp.md`; adding an operation: see the checklist in `TODO.md`'s agent-API section and regenerate `docs/reference/operations.md`). Every operation also exists as a `zarvan` command (1:1 rule). | `zarvan_core` |
| `packages/zarvan_cli` | `zarvan` CLI: `create`/`upgrade`/`lint`. | `zarvan_core` (for `lint`) |

**Dependency direction is a one-way DAG: `zarvan_core` → `zarvan_flutter`
→ `zarvan_platformer`.** Nothing may depend "backward" up this chain.
This bit us once already: `TileMap` was briefly moved into
`zarvan_platformer` (it looked platformer-specific), but
`zarvan_flutter`'s tile *renderer* needs the type to draw tiles at all —
making `zarvan_flutter` depend on `zarvan_platformer` would be
circular, since `zarvan_platformer` depends on `zarvan_flutter` for
sprites/animation. `flutter test` caught it immediately (compile
error across all three packages). The resolution, and the general
rule: a type earlier in the chain can't depend on something defined
later in it, no matter how "specific" that something's *use* seems —
genre-general **data** (like `TileMap`) belongs in `zarvan_core` even
when only one genre currently uses it seriously; only the genre-specific
**logic** operating on that data (like `TileCollisionSystem`) belongs
in `zarvan_platformer`.

Read each package's own README for its API — this file is about
*working in the repo*, not the engine's API surface.

## Non-obvious constraints (don't relitigate these)

- **2D only, no 3D, ever.** Confirmed explicitly by the project owner.
- **Android + iOS + Web** via Flutter — Flutter is the shell, not where
  engine logic lives. If you're about to put gameplay/physics/AI logic
  in `zarvan_flutter`, stop and put it in `zarvan_core` instead.
- **No other game engines** (not Flame, not Unity, not Godot) — this is
  built from scratch on purpose.
- Every `zarvan_flutter`/`zarvan_cli` package depends on `zarvan_core`
  via a **self-referencing git dependency** (same URL, same `ref: main`
  a consumer would use), not a local `path:` — this is load-bearing,
  not accidental. A local `path:` dependency makes `pub` see two
  different "descriptions" of `zarvan_core` (a resolved commit vs. a
  consumer's `ref: main`) and refuse to solve. Each such pubspec.yaml
  has a comment explaining this; read it before touching that
  dependency block. `pubspec_overrides.yaml` (gitignored-safe to keep,
  since it's ignored when the package is fetched as a git dependency)
  restores local `path:` resolution for monorepo development only.
- **KNOWN LIMITATION**: the hardcoded `ref: main` in those
  self-referencing dependencies must match whatever ref `zarvan_cli`'s
  `--ref` flag pins a generated project to, or the same conflict
  reappears. `main` always works; a tag only works if these pubspecs
  are updated to that tag as part of cutting the release. Publishing to
  pub.dev removes this constraint entirely — see TODO.md.

## Working conventions

- **No unnecessary comments.** Comments explain non-obvious *why*
  (a hidden constraint, a bug that testing caught, a design tradeoff),
  never *what* — the code already says what. Look at any existing file
  for the calibration.
- **Every change gets a test**, and the test suite must pass before
  committing: `dart test`/`dart analyze --fatal-infos` for
  `zarvan_core`/`zarvan_cli`, `flutter test`/`flutter analyze
  --fatal-infos` for `zarvan_flutter`/`zarvan_platformer`.
- **Documentation and test coverage are both non-negotiable, not
  best-effort.** Every new public class/field/function gets a doc
  comment (the *why*, per the no-unnecessary-comments rule above — not
  a restatement of the signature) before it's committed, and every new
  piece of *behavior* (not just "does it compile") gets a test that
  would actually fail without the change — a "renders/runs without
  crashing" test is acceptable only where this codebase already relies
  on that pattern (rendering-heavy `zarvan_flutter` widget tests), not
  a substitute for asserting real behavior wherever behavior can be
  asserted directly. This applies equally to bug fixes (a regression
  test) and new features — "add tests later" is not a valid state to
  commit in. When touching an existing public API that's under-
  documented, fix its doc comment too rather than leaving it as found.
- **Verify end-to-end, not just unit tests, for anything touching the
  CLI or cross-package dependency wiring.** Several real bugs in this
  repo's history were only caught by actually running `zarvan
  create` against the *pushed* repo and checking the generated project
  builds — unit tests alone would have missed them (e.g. the
  self-referencing git dependency conflict, the tile-rendering gap).
- **Commit messages explain *why*, especially for bugs**: what broke,
  how it was found (which test, which manual check), and why the fix
  works — not just "fixed X." Read recent commit messages for the
  expected depth; they're written to let a future session understand a
  decision without re-deriving it.
- Commit messages end with `Co-Authored-By: Claude Sonnet 5
  <noreply@anthropic.com>` (or whatever attribution the current session
  was given — check for a system reminder about this before committing
  if unsure).
- Only commit/push when asked, **except** this repo's owner has
  established an ongoing pattern of "keep working through TODO.md,
  commit and push each completed item" — see TODO.md for what's
  in-flight. If continuing that work, committing incrementally per
  completed item (not one giant commit) is the established norm here.

## Code quality bar (SOLID/DRY, extensibility)

- **Apply SOLID and DRY**, but weigh them against this file's other
  rules (no premature abstraction, no unnecessary complexity) rather
  than applying them mechanically — a genuine duplication (like
  `collision_math.dart` below) gets extracted; three similar lines that
  merely *look* alike don't get forced into a shared abstraction just
  to satisfy DRY on paper.
- **Single Responsibility**: a component is data; a system is one unit
  of simulation logic; a helper function does one documented thing
  (`damageEntity`, `dealDamageOnTouch`) — don't fold unrelated concerns
  into one class/function because it's convenient right now.
- **Open/Closed in practice**: prefer adding a new component/system/
  helper over branching existing logic on a type/flag to special-case
  new behavior. `installPlatformerSystems`'s `includeAnimation` flag is
  the accepted exception (a genuine on/off toggle for a whole subsystem,
  not type-based branching).
- **Dependency direction stays the DAG** (see Package map above) —
  SOLID's dependency-inversion instinct never justifies a backward
  dependency in this repo; genre-general data still belongs in
  `zarvan_core` even when a "cleaner" abstraction would colocate it
  with its one current user.
- **DRY real duplication, not superficial similarity**: two systems
  computing the same physics (`collision_math.dart`) or two components
  with the same shape belong in one shared place. Two `toJson`/
  `fromJson` pairs that happen to look alike because they follow the
  same convention are not duplication — that repetition *is* the
  convention, and collapsing it into a generic/reflective helper would
  break the plain-JSON-per-type contract the agent-facing API depends on.
- **Write for extensibility**: new code should make the *next* feature
  easier to add without rewriting this one — but don't build hooks/
  configuration for hypothetical future features nobody has asked for
  yet (see "Don't add features... beyond what the task requires"
  elsewhere in this file's spirit). When refactoring existing code
  toward this bar, keep the change behavior-preserving, keep 100% test
  coverage passing (see Validation in TODO.md), and re-run the
  benchmark suite for anything on a hot path (`packages/zarvan_core/benchmark/`,
  `packages/zarvan_platformer/benchmark/`) to confirm a "cleaner"
  version didn't regress performance.

## TODO.md

Tracks remaining engine work, checked off as items land. Check it
before starting new work — it's the source of truth for "what's left,"
kept current as items are completed. Add newly discovered work to it
rather than letting it go untracked.

## If you're extending the ECS

- New built-in component → register it in `registerCoreComponents`
  (zarvan_core), `registerFlutterComponents` (zarvan_flutter), or
  `registerPlatformerComponents` (zarvan_platformer) as appropriate,
  with `toJson`/`fromJson`, so it participates in `World.toJson()`/
  `applyPatch()`/`Level.loadInto()` like everything else. An
  unregistered component silently can't be serialized — that's a
  common mistake to check for (caught `MovementAnimationSet` missing
  its registration during this package's own test suite).
- Before adding a new type to any package, check it doesn't create a
  backward dependency per the DAG rule above — genre-general data goes
  in `zarvan_core` even if only one current package uses it heavily.
- New system → think about registration order relative to existing
  systems before writing it. `JumpSystem` had a real ordering bug (jump
  consumption ran before tile-based grounding was resolved) caught only
  by a regression test that exercised tile-only ground with no
  `PlatformBody` involved — that class of bug is easy to introduce and
  easy to miss without a test targeting the specific ordering
  dependency.
- Shared logic between two systems (e.g. circle-vs-AABB resolution used
  by both `PlatformerSystem` and `TileCollisionSystem`) belongs in a
  shared file (`collision_math.dart`), not duplicated — duplication
  here has already caused a near-miss where the two would have diverged.
