# Studio user guide

Engine Studio is the desktop editor for projects made with `game_agent create`. It
edits the same JSON files the engine loads and the CLI and agents edit, so anything you
do here can also be done (and checked) from the command line.

!!! note "Running it"
    The studio is a Flutter app in `packages/engine_studio`. From a checkout of this
    repository, run `flutter run -d macos` there. It is not distributed as an installer
    yet.

## Open a project

Start the studio and choose a project folder. A project is a folder with a
`pubspec.yaml` and an `assets/levels` folder, which `game_agent create` makes. The
project window then shows:

- a **file tree** on the left (files git sees as changed carry a mark - M, A, D, R, ? or ! - and so do the folders that contain them; the toolbar button refreshes it) (generated and hidden folders are left out), with a filter
  for levels, graphs, code, images and so on;
- the **open file** on the right: a level opens in the level editor, a graph in the graph
  editor, Dart and JSON in the code editor, images in an image view.

The icons in the top bar open, in order: the **asset browser**, a menu for **new graphs**,
the **problems** list (every level and graph problem in the project) and **project
search** (`Cmd/Ctrl+Shift+F`).

## Edit a level

Open a `*.level.json` file. The canvas shows the tile map and the entities; the toolbar
above it picks what a click or drag does:

| Tool | What it does |
|---|---|
| Select | Click an entity to select it and see its components in the inspector. |
| Move | Drag the selected entity. With **Snap to grid** on, it lands on grid points. |
| Paint | Click or drag over tiles to write the current tile id. One drag is one undo step. |
| Erase | Same, writing the empty tile. |
| Fill | Fill the connected region under the click with the current tile id. |
| Place | Add a new entity at the click, with the component chosen in the palette. |

The top bar has **Save** (`Cmd/Ctrl+S`), **Undo** and **Redo** (every edit is undoable,
and the tooltip names what will be undone), grid and snap toggles, **Show tiles** and
**Show entities** toggles (hiding only changes the drawing, not the data) and
**Delete selected**. The title shows when the level has unsaved changes; going back to the
saved state clears it.

### The inspector

Select an entity and the right-hand panel lists its components. Each field is edited with
a control that matches its type (switch, dropdown, number, text), and a bad value is
refused with a message instead of being written. The fields come from the same schemas the
validator and `docs/reference/components.md` use, so they cannot drift.

On a `sprite` component, **Pick sprite** opens a grid of the project's sprite sheets;
clicking a sprite sets `atlasId` and `region` together.

### Problems

The validation list shows every problem in the level as you edit, using the same checks
as `game_agent studio validate`: unknown components, wrong field types, and — when the
project declares its sprite sheets — sprites and atlases that do not exist. Clicking a
problem selects the entity it is about.

### Sharing a project folder

When several people edit one project in a shared or synced folder, the studio takes an
**advisory lock** on a level while it is open (`<level>.lock` next to it, naming `user@host` and
the time). If someone else holds it you get a banner, saving is switched off so nobody overwrites
the other's work, and you can **Take over** (when their editor crashed). A lock older than two
hours counts as abandoned. `game_agent studio lock` / `unlock` do the same from the command line.

If someone saves the level while you have it open, the studio notices within a couple of seconds: with no unsaved edits it
reloads and tells you; with unsaved edits it asks whether to reload (dropping yours) or keep them.

The lock is advisory (nothing stops a tool that ignores it) and meant for shared folders. With
git, use `studio merge` as a merge driver instead (see the [CLI reference](../reference/cli.md)),
and keep `*.lock` out of version control.

## Assets, prefabs and brushes

The **asset browser** lists the project's sprite sheets (with how many sprites each has),
and its images, audio, data files and prefabs. Opening a sheet shows every sprite with
the name a level refers to it by.

Sprite sheets are *declared* in `assets/studio_atlases.json`:

```json
{ "atlases": { "hero": { "image": "assets/hero.png", "manifest": "assets/hero.json" } } }
```

Undeclared sheets are still listed, but they are not offered in the sprite picker and
levels are not checked against them.

**Brushes** (the panel under the entity palette) are reusable across levels and are saved in
`assets/studio_brushes.json`:

- **New tile brush** asks for a name and a pattern: one row per line, ids separated by spaces
  or commas, `_` to leave a cell alone, `0` to erase. Clicking a brush switches to the stamp
  tool; a click on the canvas stamps the pattern with its top-left on the clicked tile, as a
  single undo step.
- **Save as prefab** turns the selected entity into `prefabs/<name>.json` and adds a prefab
  brush for it. Stamping a prefab brush places the entity (or group) at the click.

The command line has the same operations: `game_agent studio save-prefab`,
`place-prefab`, `export-tmx` and `import-tmx`.

## Graphs

Dialogue/cutscene graphs, behavior trees and state machines are edited on one canvas:
drag to pan, scroll or use the zoom buttons to zoom. Each type has its own node kinds and
its own validation, and behavior trees and state machines export to the engine's JSON in
`assets/ai/`. Problems in graphs appear in the same project-wide problems list as level
problems.

## Play-test

The play button in the level editor switches to a **Preview** that runs the level in the engine,
inside the studio, using the platformer systems. Arrow keys or A/D move, Space or W jumps, and
on-screen buttons do the same. **Fit width** scales the whole level into view, **Textures** draws
declared sprite sheets, and **Profiler** shows live simulation timings: the step cost, the entity
count, a sparkline of recent step times and the slowest systems. Pressing play always rebuilds
the world from the level as it is now, saved or not.

### Run game

The **Run game** button (rocket icon, shown for levels that belong to a project) starts your
project's own game as a separate process on the level you are editing, saved or not. The studio
writes the level to `assets/levels/playtest.level.json` (never listed as one of your levels) and
runs `flutter run -d macos` with `--dart-define=PLAYTEST_LEVEL=...` and
`--dart-define=ASSET_DIR=<project>/assets`. The game's output goes to `.studio/playtest.log`.

The generated game template reads the level from disk in this mode and **restarts its scene when
the level file is saved**, so you can leave the game running while you edit. A game not built from
the template needs to do the same (`AssetHotReloader` and `CallbackAssetHandler` in
`engine_flutter`). The device is `macos` for now, and `flutter` must be on the PATH of the app.

## Code editor

Dart and JSON files open in a built-in editor with syntax colouring, find and replace, and
Dart language-server features (completion, diagnostics, go to definition, rename with `F2`)
when a Dart SDK is found.

Blocks fold: with the Dart language server running, a chevron appears in the gutter beside each foldable block.
Click it to collapse the block down to its first line (the file is not changed, only hidden) and again to expand.
Typing, or moving the cursor into hidden code, expands everything so you never edit what you cannot see.

Choose **Get packages** in the project toolbar to run `flutter pub get` in the project and read its output.

## Settings

Per-user settings live outside any project, in `~/.game_agent/`:

- **Keyboard shortcuts** — `studio_prefs.json`:

    ```json
    { "shortcuts": { "save": "mod+k", "searchProject": "mod+shift+p" }, "locale": "fr" }
    ```

    Actions are `save`, `find`, `replace` and `searchProject`. `mod` means Command on macOS
    and Control elsewhere; `cmd`, `ctrl`, `alt` and `shift` can be combined with a letter or
    digit. A binding that cannot be read just turns that shortcut off.
- **Language** — `locale` above, plus `locales/<code>.json` containing `{"key": "text"}`.
  Keys are the ones in `StudioStrings` (`packages/engine_studio/lib/src/prefs/strings.dart`);
  anything not translated stays English. Only the project window is translatable so far.

## Updates and downloads

The **Updates** button on the open-project screen shows what a release server offers: templates,
packs, studio versions. For each item you see its size and whether it is new or an update, and
choose **Accept**, **Later** or **Skip**. Nothing downloads until you accept it and press
**Install accepted**. Each file's SHA-256 must match the signed release list before it replaces
the installed copy; a bad or interrupted download leaves the old version in place and shows a
**Retry**. **Skip** is remembered for that exact version, and a newer version asks again.

If the server cannot be reached the window says so and the studio keeps working with what is
already downloaded, so existing projects always open. A release list that is unsigned or signed
with the wrong key offers nothing and says why.

This is off until you configure it: with no server and key, the studio makes no network requests.
In `~/.game_agent/studio_prefs.json`:

```json
{ "updates": { "manifestUrl": "https://example.com/studio/manifest.json",
               "publicKey": "<base64 of the publisher's 32-byte Ed25519 key>" } }
```

The signature is fetched from `<manifestUrl>.sig` (base64). Downloads are cached in
`~/.game_agent/cache`. There is no official release server yet; this is the client side.

## Doing the same from the command line

Every studio action has a CLI equivalent, which is what makes the editor agent-friendly:
`game_agent studio validate`, `add-entity`, `remove-entity`, `set-field`, `move-entity`,
`set-layer`, `paint-tile`, `fill-region`, `import-tmx`, `export-tmx`, `export-levels`,
`save-prefab`, `place-prefab` and `project-manifest`. Run `game_agent studio --help` for
the arguments.
