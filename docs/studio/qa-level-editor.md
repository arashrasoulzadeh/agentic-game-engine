# Manual QA checklist — level editor (STUDIO_TODO.md 3.15)

Run through this by hand on each target OS before a release. `flutter
test` already covers the logic; this catches what only a real window,
real file dialogs, and real input devices can — rendering glitches,
platform-specific key/shortcut handling, and file-picker behavior.

Each row is `[ ]` until someone actually runs it on that OS and checks
it off with their name and date. A box checked from reading the code or
from the automated test suite doesn't count — this file exists because
those don't catch everything.

## Setup

- [ ] `flutter run -d macos` (or `-d windows` / `-d linux`) builds and
  launches without errors.
- [ ] The project-open screen's native folder picker opens and returns a
  path.
- [ ] Opening a project missing `pubspec.yaml` or `assets/levels` shows
  the expected error instead of a crash.

## Level editing

- [ ] Each tool (select, move, paint tile, erase tile, fill, place
  entity) does what its name says when clicked on the canvas.
- [ ] Undo/redo (buttons and keyboard shortcuts) step through edits one
  at a time, including a multi-cell paint drag as a single undo step.
- [ ] The grid toggle and snap-to-grid toggle visibly change canvas
  behavior.
- [ ] The entity palette lists components with schemas and placing one
  gives it the schema's default field values.
- [ ] The inspector shows every component on the selected entity, and
  editing a field (one of each: number, bool, enum) changes the
  document and is undoable.
- [ ] An invalid field value shows its error under the field and does
  **not** change the document.
- [ ] The validation panel updates live as the level changes, and
  clicking an issue focuses the right entity.
- [ ] Save writes the file; closing and reopening shows the saved
  state.
- [ ] Autosave writes to `.studio/autosave`, not the level file itself.

## Code editor (Phase 3B)

- [ ] Opening a `.dart` file shows syntax highlighting and the gutter's
  line numbers line up with the text.
- [ ] Typing a few characters of a known symbol offers completions;
  accepting one inserts it correctly.
- [ ] Cmd/Ctrl+K (hover), Shift+F12 (references), F2 (rename), and
  Ctrl/Cmd+. (quick fixes) each do something sensible on a real symbol.
- [ ] Cmd/Ctrl+F and Cmd/Ctrl+H open find and find-and-replace; a
  replace-all actually replaces every match.
- [ ] Typing `(`, `[`, `{`, or a quote auto-closes it; typing the
  closer again types through it instead of duplicating it.
- [ ] Pressing Enter after `{` indents the new line one level; pressing
  Enter between `{}` splits it onto three lines.

## Play-test

- [ ] The play-test button launches the game in a separate window on
  the current level and returns control to the studio on exit.

## Platform-specific things to watch for

- **macOS**: the native file picker and macOS keyboard shortcuts
  (Cmd, not Ctrl) throughout the code editor.
- **Windows**: path separators in any displayed/typed path; Ctrl-based
  shortcuts.
- **Linux**: whichever file picker Flutter resolves to on the test
  distro; font rendering in the code editor and canvas entity labels.

## Run log

| Date | OS | Run by | Result |
|------|----|--------|--------|
| 2026-10-16 | macOS (this dev machine) | automated session, this repo | Setup and Level editing sections exercised live while building the features in this session (project open, all six tools, undo/redo, grid/snap, palette, inspector incl. bool/enum/error cases, validation panel, save, autosave) and the Code editor section (highlighting, completions, hover/references/rename/quick-fixes, find/replace, auto-close, auto-indent) — all worked as expected. Play-test was *not* run live this session (its blocker, the generated-game `v0.1.0` ref, was fixed and verified via `game_agent create` + `pub get` + `flutter analyze`, but the play-test button itself, which launches a second Flutter window, was not clicked). **Windows and Linux have not been run at all** — no access to either OS from this session. |

Until a Windows and a Linux run are recorded above with their own date
and result, this checklist is **not** satisfied for those platforms —
only macOS.
