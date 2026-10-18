# API reference

The authoritative reference is the **doc comments in the source** — every
public class, field and function has one that explains *why*, not just what.
Browse them three ways.

## 1. Generated API docs (HTML)

| Package | Docs |
|---|---|
| `engine_core` | [engine_core API](https://meetarash.ir/agentic-game-engine/api/engine_core/) |
| `engine_schema` | [engine_schema API](https://meetarash.ir/agentic-game-engine/api/engine_schema/) |
| `engine_flutter` | [engine_flutter API](https://meetarash.ir/agentic-game-engine/api/engine_flutter/) |
| `engine_platformer` | [engine_platformer API](https://meetarash.ir/agentic-game-engine/api/engine_platformer/) |
| `engine_strategy` | [engine_strategy API](https://meetarash.ir/agentic-game-engine/api/engine_strategy/) |

These are rebuilt from `main` by the docs workflow. To build one locally:

```bash
cd packages/engine_flutter      # or any package
flutter pub get
dart doc .                      # → doc/api/index.html
```

## 2. Package READMEs

Each package README lists its public surface with examples:
[engine_core](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/packages/engine_core/README.md) ·
[engine_flutter](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/packages/engine_flutter/README.md) ·
[engine_platformer](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/packages/engine_platformer/README.md) ·
[engine_strategy](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/packages/engine_strategy/README.md) ·
[engine_cli](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/packages/engine_cli/README.md)

## 3. Lookup tables in this site

- [Component reference](reference/components.md) — every component's JSON shape (generated).
- [Events](reference/events.md) · [Cheat sheet](reference/cheatsheet.md) · [CLI](reference/cli.md) · [Glossary](reference/glossary.md)

## Stability

All packages are `0.x`: breaking changes happen. Once a package reaches 1.0,
only what its top-level library exports (`engine_core.dart`, …) is covered by
semver; anything under `lib/src/` is internal. See the project README's
"API stability" section.
