# ADR 0001: Hand-written component schemas (not generated or reflected)

Status: accepted (STUDIO_TODO.md decision D1)

## Context

The studio's inspector, `game_agent studio validate`, and the agent API all
need each component's field list: names, types, ranges, enum options, and
defaults. Components already hand-write `toJson`/`fromJson`, so the field
list exists only implicitly in those methods and is not queryable.

Two ways to make it queryable:

1. **Reflection or generic JSON helpers** that derive fields from the Dart type.
2. **Explicit schema descriptors** written next to each component's
   registration.

## Decision

Use explicit schema descriptors (`ComponentSchema` / `FieldSchema` in
`engine_core/lib/src/schema/`), registered with `ComponentRegistry.register`.

## Why

- CLAUDE.md requires each component's JSON to stay a plain, reviewable
  per-type contract. Reflection would hide that contract behind a generic
  helper, and the agent-facing API depends on it being explicit.
- Dart has no runtime reflection in the Flutter/AOT targets this engine ships
  to, so "derive from the type" would need a code generator. A generator is a
  build step every consumer would have to run, which we avoid for now.
- An explicit list can be reviewed in a diff. A generated one is only as
  trustworthy as the generator.

## Consequences

- Schemas are written by hand, so they can drift from `toJson`. Three tests
  guard against that:
  - each package's drift test round-trips a real sample through `fromJson`
    and `toJson` and checks the keys match the schema;
  - `component_schema_coverage_test.dart` (in `engine_platformer`, the only
    package that sees all three registries) asserts every registered
    component has a schema;
  - the same file asserts every field default is valid for its own field.
- Adding a component means adding a schema in the same registration call.
  The coverage test fails until you do.
- Revisit this decision when the component count passes about 40 **and** the
  hand-written schemas are a maintenance burden. At that point a code
  generator is worth reconsidering, and this ADR should be superseded.
