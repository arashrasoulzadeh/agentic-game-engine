# Documentation

This folder is the tutorial/concept layer on top of each package's
API-reference README. It's written for two readers at once: a human
skimming to learn the engine, and an AI coding agent that needs
concrete, copy-pasteable, unambiguous examples to work from. Every
code sample here is checked against the current source under
`packages/*/lib/src/` — if you find one that's drifted, that's a bug,
please fix it alongside whatever API change caused it.

This is markdown-in-repo today; it's written so it can become a static
docs site later without restructuring (see the "Overview → Getting
started → Concepts → Tutorials → Examples → API reference" hierarchy
below).

## Start here

| If you want to... | Read |
|---|---|
| Understand what this engine is and why | [root README](../README.md) |
| Install the CLI and get a project running | [getting-started.md](getting-started.md) |
| Understand the ECS (World/Entity/Component/System) | [concepts/ecs.md](concepts/ecs.md) |
| Understand the JSON level/content format | [concepts/content-as-data.md](concepts/content-as-data.md) |
| Understand how an AI agent drives an entity safely | [concepts/agent-api.md](concepts/agent-api.md) |
| Understand rendering (sprites, camera, lighting, HUD) | [concepts/rendering.md](concepts/rendering.md) |
| Understand platformer gameplay (gravity, jump, combat, AI) | [concepts/platformer.md](concepts/platformer.md) |
| Build something step by step | [tutorials/](tutorials/) |
| Copy a small focused snippet | [examples/](examples/) |
| Generate/browse the full API reference | [api-reference.md](api-reference.md) |

## Package API references

The full public API of each package is documented in that package's
own README, not duplicated here:

- [`packages/engine_core/README.md`](../packages/engine_core/README.md)
- [`packages/engine_flutter/README.md`](../packages/engine_flutter/README.md)
- [`packages/engine_platformer/README.md`](../packages/engine_platformer/README.md)
- [`packages/engine_cli/README.md`](../packages/engine_cli/README.md)

## For AI agents

If you're an agent (not a human) reading this to write code against
this engine:

- Every public class/method referenced in this `docs/` folder and in
  the package READMEs has a doc comment in the actual source — when in
  doubt, `grep` the class name under `packages/*/lib/src/` and read its
  doc comment directly; it explains *why*, which the method signature
  alone won't tell you.
- [concepts/agent-api.md](concepts/agent-api.md) is specifically about
  *you*: the `Behavior`/`WorldView` sandbox is the API this engine
  expects an agent to drive gameplay through at runtime, and
  [concepts/content-as-data.md](concepts/content-as-data.md) is the API
  for authoring/patching world state as JSON rather than Dart code.
- Component registration is not automatic: a component type only
  participates in `World.toJson()`/`applyPatch()`/`Level.loadInto()`
  after it's registered — see `registerCoreComponents`,
  `registerFlutterComponents` (called for you by `Scene`/`GameRunner`),
  and `registerPlatformerComponents`.

## API reference (dartdoc)

This repo does not check in generated API docs or run `dartdoc` in CI
yet. To generate the full API reference locally for any package:

```bash
cd packages/engine_core   # or engine_flutter / engine_platformer / engine_cli
dart pub get              # flutter pub get for the Flutter-dependent packages
dart doc .                # writes HTML to doc/api/
```

Then open `doc/api/index.html`. Public API doc-comment coverage (every
exported class/field/function in each package's top-level
`engine_core.dart`/`engine_flutter.dart`/`engine_platformer.dart`, per
[CLAUDE.md](../CLAUDE.md)) is treated as a hard requirement in this
repo, not best-effort — so `dart doc`'s output should already be
readable without further cleanup. If you find a public symbol with a
missing or low-quality doc comment, that's worth filing/fixing on its
own, same as any other doc-comment gap.
