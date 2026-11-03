---
template: home.html
hide:
  - navigation
  - toc
---

# ZARVAN — Where Worlds Begin.

**An agent-native, simulation-first game engine built with Dart.**

<div class="zv-pillars" markdown>
<div markdown>**Agent-Native**<br>Agents read, patch and drive worlds safely.</div>
<div markdown>**Simulation-First**<br>The simulation is the product; Flutter is the shell.</div>
<div markdown>**Data-Driven**<br>State and content are plain JSON.</div>
<div markdown>**Deterministic**<br>Seeded randomness and fixed timesteps.</div>
<div markdown>**Extensible**<br>Components, systems and behaviors.</div>
</div>

## Choose your path

<div class="grid cards" markdown>

-   :material-gamepad-variant: **I make games**

    Scaffold a game, edit levels in Studio, ship to the stores.

    [:octicons-arrow-right-24: For game makers](guides/for-users.md)

-   :material-code-braces: **I write Dart**

    Worlds, systems, components, testing and the package map.

    [:octicons-arrow-right-24: For developers](guides/for-developers.md)

-   :material-robot-outline: **I am (or build) an AI agent**

    Observe, decide and act through safe, machine-readable interfaces.

    [:octicons-arrow-right-24: For AI agents](guides/for-ai-agents.md)

-   :material-book-open-variant: **I want the idea first**

    The meaning of the name and the concept behind the engine.

    [:octicons-arrow-right-24: The concept](concepts/concept.md)

-   :material-translate: **فارسی**

    مستندات فارسی ZARVAN: معنی نام، مفاهیم و شروع سریع.

    [:octicons-arrow-right-24: مستندات فارسی](fa/index.md)

-   :material-package-variant: **What is in the box**

    Nine packages on a one-way dependency chain.

    [:octicons-arrow-right-24: Packages](packages.md)

</div>

A pure-Dart **2D game engine built for AI agents and humans to work on
together**. The world is plain JSON an agent can read and patch, content is
authored as data, and gameplay logic an agent writes runs behind a sandbox
that can't corrupt the simulation. Flutter is only the shell (rendering,
input, audio) for Android, iOS and the web.

```mermaid
flowchart LR
    subgraph Your game
      G[Game + Scenes]
    end
    G --> S[zarvan_strategy<br/>turn-based strategy]
    G --> P[zarvan_platformer<br/>platformer gameplay]
    G --> I[zarvan_idle<br/>idle / incremental games]
    S --> F[zarvan_flutter<br/>render · input · audio]
    P --> F
    I --> F
    F --> C[zarvan_core<br/>ECS · physics · content · agent API]
    S --> C
    P --> C
    C --> X[zarvan_schema<br/>component schemas]
```

## Pick your path

| I want to… | Start here |
|---|---|
| **Get a game running in 5 minutes** | [Getting started](getting-started.md) |
| **Build a platformer** | [Tutorial 1 — a tiny platformer](tutorials/01-hello-world.md) |
| **Build a turn-based strategy game** | [Tutorial 2 — turn-based strategy](tutorials/02-turn-based-strategy.md) |
| **Let an AI agent play or build the game** | [Tutorial 3 — an agent-driven game](tutorials/03-agent-driven-game.md) |
| **Write a game in a few lines** (queries, timers, save/load, tests) | [Writing games with less code](concepts/authoring.md) |
| Understand how the engine is put together | [Architecture](concepts/architecture.md) · [ECS](concepts/ecs.md) |
| Copy a focused snippet | [Examples](examples/README.md) |
| Look up a component's JSON shape | [Component reference](reference/components.md) |
| Look up an operation (CLI / MCP / REST) | [Operations reference](reference/operations.md) |
| Look up an event, system order or command | [Cheat sheet](reference/cheatsheet.md) · [Events](reference/events.md) · [CLI](reference/cli.md) |
| Fix something that isn't working | [FAQ & troubleshooting](faq.md) |

## The four ideas that shape everything

1. **World state is data.** Every entity is a bag of registered components
   that serialize to JSON. `World.toJson()` is the read path and
   `World.applyPatch()` is the write path — see
   [content as data](concepts/content-as-data.md).
2. **Systems are small and ordered.** One system, one job, run by phase and
   then registration order, which you can inspect (`world.systemOrder`) and
   check (`world.validateSystemOrder()`) — see [the ECS](concepts/ecs.md) and
   [writing games with less code](concepts/authoring.md).
3. **Agents propose, the engine disposes.** A `Behavior` reads a read-only
   `WorldView` and returns an `Action`; the engine applies it. In turn-based
   games, humans and AI alike go through `submitOrder` —
   see [the agent API](concepts/agent-api.md).
4. **Genre logic is separate from the core.** Platformer physics and
   strategy rules sit in their own packages on a one-way dependency chain, so
   a puzzle game never pays for gravity.

## Packages

| Package | What it gives you | Depends on |
|---|---|---|
| [`zarvan_core`](https://github.com/arashrasoulzadeh/zarvan/tree/main/packages/zarvan_core) | ECS, physics primitives, `TileMap`, content DSL, `WorldView`/`Behavior`, **turn clock, orders, grid navigation, combat, fog of war, selection** | `zarvan_schema` |
| [`zarvan_flutter`](https://github.com/arashrasoulzadeh/zarvan/tree/main/packages/zarvan_flutter) | `Game`/`Scene`, sprites, camera, lighting, input, audio, save/load, grid tap input | `zarvan_core` |
| [`zarvan_platformer`](https://github.com/arashrasoulzadeh/zarvan/tree/main/packages/zarvan_platformer) | Gravity, jump, tile collision, combat, patrol/follow AI, animation | core, flutter |
| [`zarvan_strategy`](https://github.com/arashrasoulzadeh/zarvan/tree/main/packages/zarvan_strategy) | One-call wiring for turn-based strategy, unit spawning | core, flutter |
| [`zarvan_cli`](https://github.com/arashrasoulzadeh/zarvan/tree/main/packages/zarvan_cli) | `zarvan create / upgrade / lint / pack-assets` | `zarvan_core` |
| [`zarvan_schema`](https://github.com/arashrasoulzadeh/zarvan/tree/main/packages/zarvan_schema) | Hand-written component schemas used by the CLI and studio | — |

## Reading this documentation

- **Concepts** explain *why* and *how it fits together*.
- **Tutorials** are linear: follow them in order and you end with a working game.
- **Examples** are standalone recipes, each verified by a test.
- **Reference** pages are lookup tables; the component page is generated from
  the source schemas.

!!! note "Code samples are tested"
    Samples in these pages are executed by tests in CI, so they cannot silently drift from the code:
    the tutorials (platformer, turn-based, agent) and the recipes in `examples/`
    (`packages/zarvan_platformer/test/doc_examples_*_test.dart`,
    `packages/zarvan_strategy/test/doc_examples_test.dart`,
    `packages/zarvan_core/test/agent_turn_based_test.dart`, `doc_examples_multiplayer_test.dart`), and the concept pages for localization,
    dialogue, AI, ECS, effects, cinematics, procedural generation, performance, settings, lighting and analytics
    (`packages/*/test/doc_examples_*_test.dart`). Pages whose samples are calls into APIs
    that have their own dedicated tests rather than a `doc_examples` file: networking (`session_test.dart`,
    `interest_management_test.dart`, `udp_transport_test.dart`, `lobby_test.dart`, `session_auth_test.dart`) and
    real-time strategy (`realtime_strategy_test.dart`, `gathering_test.dart`, `builder_test.dart`,
    `economy_test.dart`, `tech_test.dart`, `formation_test.dart`, `grid_footprint_test.dart`). Not machine-checked:
    the architecture overview (no code), the rendering page's Flutter widget snippets and the studio guide's
    click-through steps (its command-line steps are, by `first_level_tutorial_test.dart`). If a sample drifts from the code, that is a bug - please open an issue or fix both.

## For AI agents reading this

- Every public symbol has a doc comment that explains *why*; `grep` the class
  under `packages/*/lib/src/` for the authoritative version.
- A component only participates in `toJson` / `applyPatch` / `Level.loadInto`
  once registered — see
  [FAQ: "my component isn't saved"](faq.md#my-component-isnt-saved-or-loaded).
- Drive gameplay through `Behavior` (real-time) or `submitOrder`
  (turn-based). Don't mutate stores from outside the system that owns the data.
- Start with [concepts/agent-api.md](concepts/agent-api.md) and
  [tutorial 3](tutorials/03-agent-driven-game.md).

## Project links

[Source on GitHub](https://github.com/arashrasoulzadeh/zarvan) ·
[Changelog](https://github.com/arashrasoulzadeh/zarvan/blob/main/CHANGELOG.md) ·
[Roadmap (TODO.md)](https://github.com/arashrasoulzadeh/zarvan/blob/main/TODO.md) ·
[Contributing](https://github.com/arashrasoulzadeh/zarvan/blob/main/CONTRIBUTING.md)
