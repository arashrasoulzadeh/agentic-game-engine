# engine_flutter

The Flutter shell for [engine_core](../engine_core/README.md): rendering,
input, camera, audio, and save/load. Contains **no gameplay logic** —
it reads `World` component state and renders it, converts raw Flutter
input into engine-readable state, and provides the platform services
(storage, audio) a real game needs. Everything else (physics, AI,
content) lives in `engine_core`, which stays Flutter-free.

## Install

```yaml
dependencies:
  engine_flutter:
    git:
      url: https://github.com/arashrasoulzadeh/agentic-game-engine.git
      path: packages/engine_flutter
      ref: main
```

(Normally you don't add this directly — `game_agent create` wires it up
for you. See [engine_cli](../engine_cli/README.md).)

## Quick start: the `Game` API

This is the intended way to build a game — extend `Game`, call `runGame`:

```dart
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await GameConfig.loadFromAsset('assets/game_config.json');
  runGame(MyGame(config));
}

class MyGame extends Game {
  MyGame(this._config);
  final GameConfig _config;

  @override
  GameConfig get config => _config;

  @override
  void populateWorld(World world) {
    // GameRunner already built `world` (sized from config) and called
    // registerCoreComponents/registerFlutterComponents for you — just
    // add your own systems and spawn entities.
    world.addSystem(MovementSystem());
    world.addSystem(CollisionSystem());
    // ...
  }
}
```

`Game` also has optional overrides you'll commonly want:

| Method | Default | Override for |
|---|---|---|
| `loadAssets()` | empty `AtlasRegistry` | Loading sprite atlases before the first frame |
| `createCamera(world)` | centered on the world | Following the player from frame one |
| `createInputController()` | `null` (no keyboard) | Custom key bindings |
| `cameraFollowEntity(world)` | `null` (static camera) | Camera-follow target (usually the player) |
| `buildLoadingScreen(context)` | centered spinner | A branded splash screen |
| `onPause()` / `onResume()` | no-op | Save-on-pause, pausing audio, etc. |

`GameRunner` (what `runGame` wraps in a `MaterialApp`/`Scaffold`) also
handles app-lifecycle pause/resume automatically (`config.pauseOnBackground`)
and applies `config.orientation` on startup.

## `GameConfig`

JSON-serializable app settings, loaded from a bundled asset:

```json
{
  "title": "My Game",
  "orientation": "landscape",
  "worldWidth": 800,
  "worldHeight": 480,
  "backgroundColor": 4278190080,
  "showFpsOverlay": false,
  "pauseOnBackground": true
}
```

`orientation` is one of `"portrait"`, `"landscape"`, `"auto"` —
**note: this only has any effect on Android/iOS**; browsers ignore
`SystemChrome.setPreferredOrientations` entirely, so on web the
viewport shape is just whatever the browser window is.

## Components/systems this package adds

Registered via `registerFlutterComponents(world)` (called automatically
by `GameRunner`):

| Component | Purpose |
|---|---|
| `Sprite(atlasId, region, rotation, scaleX, scaleY)` | Which atlas region to draw at this entity's `Position` |
| `AnimationState(clip, frameIndex, elapsed, playing)` | Playback state for a looping/one-shot frame sequence |
| `InputState(pressedActions)` | Logical input actions currently pressed (`"left"`, `"jump"`, ...) |

Plus `AnimationSystem`, which advances `AnimationState` and writes the
current frame's region onto the entity's `Sprite`.

Building an `AnimationClip` from a sprite sheet's numbered frames
(`walk_0`, `walk_1`, ...)? `AnimationClip.sequence('walk', 'walk', 8)`
generates the region list for you instead of writing
`List.generate(8, (i) => 'walk_$i')` at every call site.

## Sprites and atlases

```dart
final atlas = await SpriteAtlas.loadFromAssets(
  imageAssetPath: 'assets/characters.png',
  manifestAssetPath: 'assets/characters.json',
);
atlasRegistry.register('characters', atlas);
```

Manifest shape:

```json
{"regions": {"player_idle": {"x": 0, "y": 0, "w": 32, "h": 32}}}
```

`Sprite` components store an atlas *id* + region *name* (plain
strings), not a decoded image — so they stay JSON-serializable for
agent-authored content. `AtlasRegistry` resolves ids to the actual
loaded `SpriteAtlas` at render time.

## Input

```dart
@override
InputController createInputController() => InputController();
```

Default bindings: arrow keys → `"left"`/`"right"`/`"up"`/`"down"`,
space → `"jump"`. Pass a custom `bindings` map to `InputController` for
your own scheme. To let a system read input, attach the *same*
`InputState` instance (`controller.state`) as a component on the
player entity in `populateWorld` — see `test_game`'s `main.dart` for a
worked example, including the input-reading system itself
(`_PlayerInputSystem`).

## Audio

```dart
final audio = AudioManager();
await audio.playSound('sfx/jump.wav');
await audio.playMusic('music/theme.mp3', loop: true);
```

Recommended pattern: listen on `world.events` and call `playSound` from
there, not from inside a `System` — keeps simulation logic decoupled
from playback.

## Save/load

```dart
await SaveGame.save(world);                    // default slot
final restored = await SaveGame.load(newWorld); // returns false if none
```

Uses `shared_preferences` (works identically on Android/iOS/web/desktop
— raw `File` I/O doesn't exist on web at all). `load` spawns fresh
entities into `newWorld` via `Level.loadInto` — call it on a freshly
constructed `World`, not one `populateWorld` has already filled.
Multiple save slots via the `slot` parameter.

## Camera

```dart
final camera = Camera(x: 0, y: 0, zoom: 1);
camera.follow(playerX, playerY, viewportSize: size, worldWidth: w, worldHeight: h);
```

`follow` clamps so the viewport never shows past world bounds (unless
the world is smaller than the viewport, in which case it just centers).

## Testing

```bash
flutter test
flutter analyze --fatal-infos
```

Note: fully simulating platform plugins (audio, shared_preferences) in
widget tests has diminishing returns past a point — see
`test/audio_manager_test.dart`'s comment for where this project drew
that line. Real playback/orientation/lifecycle behavior should be
verified on an actual device, not assumed from passing unit tests.
