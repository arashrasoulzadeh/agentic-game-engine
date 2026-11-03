# Studio: open work and checks

Open items for `packages/zarvan_studio`. Design and delivered phases:
[design.md](design.md). Delete an item once shipped; what shipped goes in
[CHANGELOG.md](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/CHANGELOG.md).

## Distribution (3.22)

- [ ] Stand-in packing is CI-checked for macOS `.dmg` (`tool/verify_dmg_pack.sh`),
      Linux AppDir/AppImage (`tool/verify_appimage_pack.sh`) and the Windows zip/MSI
      hook (`tool/verify_windows_pack.sh`). Still open:
    - a real `flutter build macos --release` (the FlutterMacOS.framework arch check failed on the dev machine);
    - WiX `.msi` authoring;
    - `appimagetool` on release hosts;
    - code signing and notarization;
    - a release server and signing key (the update client exists; nothing to talk to).

## Tests

- [ ] **Flaky `play_test_test.dart`**: "devices and stopping the device in use appears
      in the launch arguments" failed once in CI with "failed after test completion"
      (a timer or stream outliving the test). Not reproduced locally.
- [ ] `rename_test.dart` is sensitive to load timing; it uses larger retry budgets
      but can still flake on a busy machine.

## Features

- [ ] **Debugger**: its own phase, not in the current IDE scope.
- [ ] Not scheduled: play-test process profiling, a live cursor feed, and a visual
      three-way merge UI (`studio merge` covers the CLI).

## Docs

- [ ] A studio screenshot with real entity-label text (`UPDATE_SCREENSHOTS=1`
      regenerates `docs/img/`).
