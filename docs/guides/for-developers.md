# For developers

You write Dart on top of ZARVAN or work on the engine itself.

## Mental model in one minute

- A **`World`** holds entities (integer ids), **components** (plain data in
  stores) and **systems** (small rules run in order every step).
- Systems talk through components and the **`EventBus`**, never to each other.
- Simulation is separate from presentation: `zarvan_core` is pure Dart;
  `zarvan_flutter` renders and reads input.

Read: [Concept](../concepts/concept.md) → [Architecture](../concepts/architecture.md)
→ [The ECS](../concepts/ecs.md) → [Writing games with less code](../concepts/authoring.md).

## Which package do I depend on?

See [Packages](../packages.md). Dependencies run one way:
`zarvan_schema` → `zarvan_core` → `zarvan_flutter` → `zarvan_platformer` / `zarvan_strategy` / `zarvan_idle`.

## Everyday recipes

| I want to… | Read |
|---|---|
| Add a kind of data to entities | [The ECS](../concepts/ecs.md), [Cheat sheet](../reference/cheatsheet.md) |
| Add a rule that runs every tick | [The ECS](../concepts/ecs.md) (system order) |
| React to something that happened | [Events](../reference/events.md) |
| Make an NPC decide things | [AI trees and state machines](../concepts/ai.md), [Custom Behavior](../examples/custom-behavior.md) |
| Save and load | [Save / load](../examples/save-load.md) |
| Test headless | `GameTester` in [Writing games with less code](../concepts/authoring.md) |
| Network a game | [Networking](../concepts/networking.md) |
| Tune performance | [Performance](../concepts/performance.md) |

## Working on the engine

```bash
git clone https://github.com/arashrasoulzadeh/zarvan.git && cd zarvan
(cd packages/zarvan_core && dart test && dart analyze --fatal-infos)
(cd packages/zarvan_flutter && flutter test && flutter analyze --fatal-infos)
```

Rules that bite: a new component must be registered or it will not serialize;
shared logic goes in one shared file; every public symbol gets a doc comment
and every behaviour a test. See [CONTRIBUTING](https://github.com/arashrasoulzadeh/zarvan/blob/main/CONTRIBUTING.md)
and [Working on the docs](../contributing-docs.md). Design decisions are
recorded as [ADRs](../adr/0001-hand-written-component-schemas.md).
