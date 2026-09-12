# CLAUDE.md

Guidance for Claude (or any AI agent) working in this repository.

## What this repo is

A pure-Dart 2D game engine, built to be **AI-agent-friendly** as a
first-class design goal, not an afterthought: world state is
JSON-serializable data an agent can read/patch, content is authored as
data (not code), and a `Behavior`/`WorldView` sandbox lets an agent
drive an entity at runtime without any path to corrupting simulation
state. Flutter is used only as the cross-platform rendering/input/audio
shell — the actual engine (`engine_core`) has zero Flutter dependency.

**This repo is the engine library itself, not a game.** There is
deliberately no sample app checked into git — `test_game/` (a real,
playable sample platformer exercising every major engine feature) is
gitignored and exists only locally for manual verification. Never
un-gitignore it or commit a sample app to this repo; that decision was
made explicitly (see the "Remove root sample app" commit).

## Package map

| Package | What | Depends on |
|---|---|---|
| `packages/engine_core` | ECS, physics, content DSL, agent API. Pure Dart, no Flutter. | nothing engine-internal |
| `packages/engine_flutter` | Rendering, input, camera, audio, save/load. | `engine_core` |
| `packages/engine_cli` | `game_agent` CLI: `create`/`upgrade`/`lint`. | `engine_core` (for `lint`) |

Read each package's own README for its API — this file is about
*working in the repo*, not the engine's API surface.

## Non-obvious constraints (don't relitigate these)

- **2D only, no 3D, ever.** Confirmed explicitly by the project owner.
- **Android + iOS + Web** via Flutter — Flutter is the shell, not where
  engine logic lives. If you're about to put gameplay/physics/AI logic
  in `engine_flutter`, stop and put it in `engine_core` instead.
- **No other game engines** (not Flame, not Unity, not Godot) — this is
  built from scratch on purpose.
- Every `engine_flutter`/`engine_cli` package depends on `engine_core`
  via a **self-referencing git dependency** (same URL, same `ref: main`
  a consumer would use), not a local `path:` — this is load-bearing,
  not accidental. A local `path:` dependency makes `pub` see two
  different "descriptions" of `engine_core` (a resolved commit vs. a
  consumer's `ref: main`) and refuse to solve. Each such pubspec.yaml
  has a comment explaining this; read it before touching that
  dependency block. `pubspec_overrides.yaml` (gitignored-safe to keep,
  since it's ignored when the package is fetched as a git dependency)
  restores local `path:` resolution for monorepo development only.
- **KNOWN LIMITATION**: the hardcoded `ref: main` in those
  self-referencing dependencies must match whatever ref `engine_cli`'s
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
  `engine_core`/`engine_cli`, `flutter test`/`flutter analyze
  --fatal-infos` for `engine_flutter`.
- **Verify end-to-end, not just unit tests, for anything touching the
  CLI or cross-package dependency wiring.** Several real bugs in this
  repo's history were only caught by actually running `game_agent
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

## TODO.md

Tracks remaining engine work, checked off as items land. Check it
before starting new work — it's the source of truth for "what's left,"
kept current as items are completed. Add newly discovered work to it
rather than letting it go untracked.

## If you're extending the ECS

- New built-in component → register it in `registerCoreComponents`
  (engine_core) or `registerFlutterComponents` (engine_flutter), with
  `toJson`/`fromJson`, so it participates in `World.toJson()`/
  `applyPatch()`/`Level.loadInto()` like everything else. An
  unregistered component silently can't be serialized — that's a
  common mistake to check for.
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
