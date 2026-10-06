# ADR 0004: Component schemas live in a pure-Dart package, engine_schema

Status: accepted. Supersedes the location part of ADR 0001 (the schemas
themselves are unchanged in design).

## Context

ADR 0001 put each component's schema next to its registration, in the package
that owns the component. That works for the engine and the studio, which can
import the Flutter packages. It does not work for `game_agent studio validate`,
which is pure Dart and only depends on `engine_core`: it cannot import
`engine_flutter` or `engine_platformer` to learn their components.

## Decision

Move the schema types and every component's schema into a new pure-Dart
package, `engine_schema`. Registrations reference the named constants
(`schema: spriteSchema`). `allComponentSchemas` maps each registered name to
its schema, for tools that cannot register components.

## Why

- A tool that only needs to check data should not import rendering code.
  `engine_schema` depends on nothing, so the CLI and the studio can validate
  every component without the Flutter SDK.
- The schemas describe field names, types, and ranges. They do not depend on
  the component classes, so they can live apart from them without a cycle:
  `engine_schema` sits at the bottom of the DAG.
- One source of truth: each schema is defined once, so the CLI and the engine
  cannot disagree about a component's fields.

## Consequences

- `engine_core` depends on `engine_schema` and re-exports the three schema
  types, so existing imports keep working.
- `required` is now meaningful. A key is required when its `fromJson` casts it
  with no fallback, which was derived by reading each `fromJson`. Before this,
  every missing key was an error, which rejected levels the engine loads fine.
- The legend form of `tileMap` is validated by its own rules, because the flat
  schema describes only the flat `tiles` form the engine writes.
- Releasing: `engine_schema` is pinned by git ref like the other packages. The
  monorepo `pubspec_overrides.yaml` files resolve it locally.
