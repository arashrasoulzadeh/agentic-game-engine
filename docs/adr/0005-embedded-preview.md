# ADR 0005: Play runs an embedded preview in the studio

Status: accepted. Supersedes ADR 0003 (play-test as a separate process).

## Context

ADR 0003 ran play-test as a separate process so a game crash could not take the
editor down. In use, that approach failed for the designer: starting a game
needs a Flutter desktop target in the game project, the launched process needs
the shell's PATH, and a launch error gives no feedback inside the editor. The
designer also wanted to see the level running in the same window they edit it
in.

## Decision

Pressing play switches the level screen to a **Preview** mode. The studio builds
a live engine `World` from the level as it is in memory, installs the platformer
systems, and steps it on a ticker. The result is drawn in the studio window.

## Why

- Nothing needs to be installed or configured in the game project.
- The preview runs the edited level, unsaved changes included, with no snapshot
  file and no waiting for a build.
- Errors are shown inside the Preview tab instead of being lost to a process.

## Consequences

- A native crash in the engine can still take the studio down. Engine errors
  that Dart can catch are shown in the Preview tab; a native crash cannot be.
- The first slice runs the engine's physics but has no player input yet, and it
  draws tiles and entity markers, not sprites. Sprites need the game's atlases,
  which come with the asset browser (5.1); game code in the game project is not
  loaded at all yet.
- `PlayTest` (the separate-process launcher) is kept as a fallback for a game
  whose code the studio cannot load. It is not reached from the play button.
