# Remaining work

Tracked here so progress survives across sessions. Check items off as
they land; add new ones as they're discovered. Rough priority order,
top to bottom — not strict, adjust as dependencies emerge.

## Engine (engine_core)

- [x] Platformer physics: gravity component/system, ground detection,
      jump support, one-way platforms
- [ ] Tilemaps: tile-based level representation + collision against
      tile grids (distinct from the current per-entity spatial hash)
- [ ] Persistence: save/load a `World` snapshot to/from disk (builds on
      existing `toJson`/`applyPatch`)
- [ ] Level lint: expose `Level.validate()` as a `game_agent` CLI
      subcommand so a level file can be checked without running the game

## Rendering/platform (engine_flutter)

- [ ] Real sprite asset pipeline: load an actual sprite sheet image via
      `rootBundle` + `ui.instantiateImageCodec`, plus a manifest format
      for named regions (replacing the runtime-generated placeholder)
- [ ] Audio: sound effect + music playback, likely via a small wrapper
      package, with an engine_core-facing abstraction like `InputState`
      has for input

## Tooling / release

- [ ] Cut a real `v0.1.0` git tag once the API stops churning; update
      `engine_flutter`'s self-referencing `engine_core` git ref to match
      (see the KNOWN LIMITATION comment in
      `packages/engine_flutter/pubspec.yaml`)
- [ ] Publish `engine_core`/`engine_flutter`/`engine_cli` to pub.dev —
      removes the git-ref-matching constraint entirely via normal semver
- [ ] Test on a real Android/iOS device (or at least a release build) —
      everything so far has only been verified on Flutter web debug
      builds; orientation lock, lifecycle pause/resume, and real-world
      performance are unverified outside that

## Validation

- [ ] Build one real (small but complete) game on the engine — every
      test so far uses the CLI's placeholder demo, not actual gameplay
