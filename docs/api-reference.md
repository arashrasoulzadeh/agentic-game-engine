# API reference

The authoritative reference is the **doc comments in the source** — every
public class, field and function has one that explains *why*, not just what.
Browse them three ways.

## 1. Generated API docs (HTML)

| Package | Docs |
|---|---|
| `zarvan_core` | [zarvan_core API](https://meetarash.ir/agentic-game-engine/api/zarvan_core/) |
| `zarvan_schema` | [zarvan_schema API](https://meetarash.ir/agentic-game-engine/api/zarvan_schema/) |
| `zarvan_flutter` | [zarvan_flutter API](https://meetarash.ir/agentic-game-engine/api/zarvan_flutter/) |
| `zarvan_platformer` | [zarvan_platformer API](https://meetarash.ir/agentic-game-engine/api/zarvan_platformer/) |
| `zarvan_strategy` | [zarvan_strategy API](https://meetarash.ir/agentic-game-engine/api/zarvan_strategy/) |

These are rebuilt from `main` by the docs workflow. To build one locally:

```bash
cd packages/zarvan_flutter      # or any package
flutter pub get
dart doc .                      # → doc/api/index.html
```

## 2. Package READMEs

Each package README lists its public surface with examples:
[zarvan_core](https://github.com/arashrasoulzadeh/zarvan/blob/main/packages/zarvan_core/README.md) ·
[zarvan_flutter](https://github.com/arashrasoulzadeh/zarvan/blob/main/packages/zarvan_flutter/README.md) ·
[zarvan_platformer](https://github.com/arashrasoulzadeh/zarvan/blob/main/packages/zarvan_platformer/README.md) ·
[zarvan_strategy](https://github.com/arashrasoulzadeh/zarvan/blob/main/packages/zarvan_strategy/README.md) ·
[zarvan_cli](https://github.com/arashrasoulzadeh/zarvan/blob/main/packages/zarvan_cli/README.md)

## 3. Lookup tables in this site

- [Component reference](reference/components.md) — every component's JSON shape (generated).
- [Events](reference/events.md) · [Cheat sheet](reference/cheatsheet.md) · [CLI](reference/cli.md) · [Glossary](reference/glossary.md)

## Stability

All packages are `0.x`: breaking changes happen. Once a package reaches 1.0,
only what its top-level library exports (`zarvan_core.dart`, …) is covered by
semver; anything under `lib/src/` is internal. See the project README's
"API stability" section.
