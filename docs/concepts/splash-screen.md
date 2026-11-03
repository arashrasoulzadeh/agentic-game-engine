# Splash screen and loading progress

Every game starts on a splash screen: the logo, a progress bar that fills as
the first scene loads, and, at the bottom, the engine build the game was
compiled against (`ZARVAN engine · <commit>`).

## Change the artwork

Override `Game.splash` (or pass `splash:` to `WaveCombatGame`) with a
`SplashConfig`. Every field is optional; the default is the ZARVAN logo.

```dart
class MyGame extends Game {
  @override
  SplashConfig get splash => const SplashConfig(
    logo: AssetImage('assets/logo.png'),
    title: 'My Game',
    accentColor: Color(0xFFC8A66A),
    minDuration: Duration(milliseconds: 1500),
  );
}
```

| Field | Meaning |
|---|---|
| `logo` | Any `ImageProvider`. Null shows the bundled ZARVAN logo. |
| `logoSize` | Logo size in logical pixels. |
| `title` | Game name under the logo. |
| `backgroundColor` | Null uses `GameConfig.backgroundColor` behind the default dark splash colour. |
| `accentColor` | Progress bar and engine-version colour. |
| `showEngineVersion` | Hide the footer with `false`. |
| `minDuration` | Keep the splash up at least this long. First scene only. |

To replace the whole screen, override `Game.buildLoadingScreen`; it can listen
to `Game.loadingProgress` (`fraction` and `label`) for the same progress.

## The engine commit in the footer

The footer shows `ZARVAN_COMMIT`, a compile-time define:

- `zarvan build-release` passes it for you: the commit from `pubspec.lock` for
  a git dependency, or `git describe --tags --always --dirty` of the engine
  checkout for a local `path:` dependency.
- Otherwise pass `--dart-define=ZARVAN_COMMIT=<value>` to `flutter run` or
  `flutter build`. Without it the footer reads `ZARVAN engine · dev`.

Progress is reported by `GameRunner`: preparing, world, assets (per asset when
the scene calls `reportAssetProgress(done, total)`), warming up, ready.

## Warm-up

After the world is populated and before the first frame, the engine warms what
the world will actually use: it compiles the lighting, GPU-shadow and
normal-map shaders only if the world has lights or normal-mapped sprites, and
draws each once offscreen so the GPU pipeline is built before play. Override
`Scene.warmUp(world)` to prime your own caches or pools; it runs on the splash,
before `onEnter`.
