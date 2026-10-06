# ADR 0002: The command model lives in engine_core

Status: accepted (STUDIO_TODO.md decision D2, default recommendation)

## Context

Every studio edit is an `EditCommand` with apply/revert. Put the command types
in `studio` (Flutter UI) or in `engine_core` (plain Dart)?

## Decision

In `engine_core/lib/src/command/`.

## Why

- Agents and the CLI must make the same edits a designer makes. If commands
  lived in the Flutter app, an agent would have to drive the UI or duplicate
  the logic, which is the second-class treatment the PRD rules out (2.10).
- The commands operate on `LevelDocument`, which is plain data. Nothing in
  them needs Flutter, so `engine_core` is the right home under the DAG rule.
- Undo correctness is then testable with `dart test`, with no widget tree.

## Consequences

- The studio owns only presentation: which command a gesture produces, and
  when a stroke starts and ends (`CommandHistory.executeGroup`).
- Commands mutate JSON in place. Anything that must not change is copied
  before the edit, not inside the command.
