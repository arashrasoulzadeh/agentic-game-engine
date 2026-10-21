# Settings and accessibility options

`PlayerOptions` is the data model for a player's settings; `PlayerOptionsManager` loads, changes,
saves and announces them; `SettingsMenuScene` draws a menu bound to them. **The engine stores and
presents the options. Applying them to the game is your code's job** - see
[What the engine applies](#what-the-engine-applies).

Samples are executed by `packages/engine_core/test/doc_examples_player_options_test.dart` and
`packages/engine_flutter/test/doc_examples_settings_test.dart`.

## The options

| Group | Fields |
|---|---|
| Audio | `masterVolume`, `musicVolume`, `sfxVolume` (0..1) |
| Controls | `controlScheme`, `keyboardBindings`, `gamepadBindings`, `touchBindings` (action -> key/button) |
| Accessibility | `textScale` (0.5..3), `highContrast`, `colorblindMode` (`none`, `protanopia`, `deuteranopia`, `tritanopia`), `reduceMotion`, `screenShakeIntensity` (0..1), `dialogueSpeed` |
| Other | `locale`, `showFpsOverlay`, and a free-form `custom` map for your own keys |

Everything has a default, and `PlayerOptions.fromJson` fills in whatever a saved file lacks, so adding
an option in a later version never breaks an old save.

## Load, change, save, listen

```dart
final storage = InMemoryPlayerOptionsStorage();           // tests; see persistence below
final options = PlayerOptionsManager(storage);
options.addListener((o) => audio.setMasterVolume(o.masterVolume));

await options.load();                                     // defaults if nothing is stored

await options.setOption('masterVolume', 0.4);             // one value
await options.update((o) => o.copyWith(reduceMotion: true, textScale: 1.5));   // several
await options.setOption('difficulty', 'hard');            // unknown key -> options.custom
options.getOption('masterVolume');                        // 0.4
```

- Every change is **clamped** (volumes to 0..1, `textScale` to 0.5..3, shake to 0..1), saved to
  storage and then sent to listeners.
- `load()` also notifies, so UI built from the options initialises itself from one place.
- Keep the manager somewhere long-lived (your `Game`), not in a scene.

## Persistence

Storage is an interface (`PlayerOptionsStorage`: `load`, `save`, `clear`). `engine_flutter` provides
`SharedPreferencesPlayerOptionsStorage`, and `createPlayerOptionsManager()` builds a manager on it and
loads it:

```dart
final options = await createPlayerOptionsManager();       // survives restarts on every platform
```

An unreadable stored value is treated as "nothing stored" rather than crashing.

## A settings menu

Subclass `SettingsMenuScene`, give it the manager, and list widgets; each is bound to an option key and
writes back through the manager. Types: toggle, slider, dropdown, list, key binding, section header.

```dart
class MySettings extends SettingsMenuScene {
  @override
  String? get title => 'Settings';

  @override
  List<SettingsWidgetSpec> get widgets => const [
        SettingsSliderSpec(id: 'vol', label: 'Volume', optionKey: 'masterVolume', min: 0, max: 1),
        SettingsToggleSpec(id: 'motion', label: 'Reduce motion', optionKey: 'reduceMotion'),
      ];

  @override
  void onValueChanged(String key, dynamic value) {
    // Apply immediately, e.g. audio.setMasterVolume(value) when key == 'masterVolume'.
  }
}

scenes.pushSettingsMenu(MySettings()..optionsManager = options);   // as an overlay
```

`AccessibilitySettingsMenu` is ready-made, with high contrast, colorblind mode, reduce motion, text size
and shake intensity.

## What the engine applies

Be clear about this when you ship an accessibility menu:

- **Camera shake has a switch:** `Camera.shakeIntensity` multiplies every shake (`0` none, `1` as authored).
  Bind it once: `options.addListener((o) => camera.shakeIntensity = o.screenShakeIntensity);`. The engine does
  not read `PlayerOptions` itself.
- **Not applied by the engine:** volumes, `textScale`, `highContrast`, `reduceMotion`, `dialogueSpeed`. They
  are values for *your* systems to honour (skip your own animations when `reduceMotion` is on, scale your own
  UI text, and so on).

- **`colorblindMode` is stored but not rendered.** `EngineView` has a hook for a colorblind
  simulation pass, but it is an unimplemented placeholder; choosing a mode currently changes nothing on
  screen. If you need colorblind support today, offer palettes or shapes your art can switch between.
- `showFpsOverlay` as a `GameConfig` field does work (debug builds); the option is just the player-facing
  switch for you to wire to it.

A setting the player can change that does nothing is worse than no setting, so wire the options you
expose and leave the others out of your menu.
