# zarvan_schema

Pure-Dart component schemas for the ZARVAN.

Each registered component (in `zarvan_core`, `zarvan_flutter`, and
`zarvan_platformer`) has a `ComponentSchema` here: its field names, types,
ranges, enum options, and defaults. The `zarvan studio validate` CLI and
the studio read these to check levels without importing Flutter.

The schemas are data. Each one must match its component's `toJson` keys, and
the drift tests in the engine packages enforce that. See
`docs/adr/0001-hand-written-component-schemas.md` and
`docs/adr/0004-schemas-in-engine-schema.md`.
