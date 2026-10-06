# ADR 0003: Play-test runs as a separate process

Status: superseded by ADR 0005 (embedded preview). Kept as the fallback launcher.

(Originally accepted as STUDIO_TODO.md decision D4, default recommendation.)

## Context

A designer presses "play" to try the level they are editing. Should the game
run inside the studio's process, or in a separate one?

## Decision

Separate process. The studio saves a snapshot of the level, launches the game
pointed at it, and regains focus when the game exits.

## Why

- A crash in the game under test cannot take down the editor and lose unsaved
  work.
- The game runs its real `GameRunner` with its real window and input. An
  embedded runner would need the studio's widget tree to host the engine's
  rendering, which is a larger coupling than v1 needs.
- The snapshot step means play-test always runs the saved data, which is the
  data that ships.

## Consequences

- Play-test is slower to start than an embedded runner would be.
- The embedded option stays open as phase 7.4, if designers ask for it.
