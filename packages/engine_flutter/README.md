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
| `createInputController()` | `null` (no keyboard/touch input) | Custom key bindings — also drives on-screen touch controls, see below |
| `cameraFollowEntity(world)` | `null` (static camera) | Camera-follow target (usually the player) |
| `buildLoadingScreen(context)` | centered spinner | A branded splash screen |
| `onPause()` / `onResume()` | no-op | Save-on-pause, pausing audio, etc. |
| `onScreenButtons()` | one `"jump"` button | Which touch buttons to show and what action each sets |
| `onScreenJoystickVertical` | `false` | Set `true` if the joystick should also drive `"up"`/`"down"` (top-down games) |

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
  "pauseOnBackground": true,
  "onScreenControls": "auto"
}
```

`orientation` is one of `"portrait"`, `"landscape"`, `"auto"` —
**note: this only has any effect on Android/iOS**; browsers ignore
`SystemChrome.setPreferredOrientations` entirely, so on web the
viewport shape is just whatever the browser window is.

`onScreenControls` is one of `"auto"` (shown on Android/iOS, hidden
elsewhere), `"on"`, `"off"` — see [Mobile touch controls](#mobile-touch-controls).

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
player entity in `populateWorld` (`engine_platformer`'s `spawnPlayer`
does this for you — see its README).

### Mobile touch controls

Returning an `InputController` from `createInputController()` also
gets you an on-screen joystick + buttons for free — `GameRunner` shows
`OnScreenControls`, wired to the *same* controller, whenever
`config.onScreenControls` resolves to true (Android/iOS by default
under `"auto"`). No separate touch-handling code needed: the joystick
and buttons call `controller.setAction(...)`, the exact same method a
keyboard binding uses internally, so `PlatformerInputSystem` (or any
system reading `InputState`) never knows whether an action came from a
key press or a finger.

```dart
@override
List<OnScreenButtonSpec> onScreenButtons() => const [
      OnScreenButtonSpec('jump', 'JUMP'),
      OnScreenButtonSpec('attack', 'ATK'),
    ];

@override
bool get onScreenJoystickVertical => false; // true for top-down games
```

Force controls on/off regardless of platform via `GameConfig.onScreenControls`
(useful for testing touch controls in a desktop browser).

The joystick is **floating** by default (`VirtualJoystick.floating`,
default `true`): invisible until touched, then drawn wherever the
finger lands within its touch region — not fixed permanently in the
corner. This is the standard mobile-game pattern, and it's what avoids
a persistent joystick overlapping gameplay it can't get out of the way
of (e.g. a camera-followed player rendered underneath a fixed-position
joystick near a world edge — found during manual testing of this
engine's own sample game). Pass `floating: false` for the classic
always-visible joystick instead. `VirtualJoystick`/
`VirtualButton` also work standalone if `OnScreenControls`'s
joystick-bottom-left/buttons-bottom-right layout doesn't fit your game.

#### Custom/sprite buttons

`OnScreenButtonSpec('jump', 'JUMP')` (the default constructor) gives
you a plain colored circle with a label. For a button styled to match
your game's art, use `OnScreenButtonSpec.custom(...)` instead:

```dart
@override
List<OnScreenButtonSpec> onScreenButtons() => const [
      OnScreenButtonSpec.custom(
        'jump',
        atlasId: 'ui',            // an atlas registered via loadAssets()
        region: 'button_jump',    // region drawn while idle
        pressedRegion: 'button_jump_pressed', // swapped in while held
        diameter: 72,
      ),
      OnScreenButtonSpec.custom(
        'attack',
        label: 'ATK',             // no atlasId/region -> falls back to
        shape: BoxShape.rectangle, // colored shape + label instead
        borderRadius: BorderRadius.all(Radius.circular(8)),
        idleColor: Color(0xFF883322),
        pressedColor: Color(0xFFCC5533),
      ),
    ];
```

`atlasId` is resolved against the same `AtlasRegistry` returned by
`loadAssets()` — the one already backing your game's sprites. If
`atlasId`/`region` are omitted, or the id doesn't resolve (e.g. the
atlas hasn't loaded), the button falls back to the color/shape/label
rendering, so `OnScreenButtonSpec.custom` is safe to use even before
assets finish loading.

#### Feel: haptics, press animation, analog joystick

Every button scales down slightly (`AnimatedScale`, 80ms) while held,
and both buttons and the joystick play a short vibration
(`HapticFeedback.selectionClick()`, a no-op on platforms without
haptic support such as web) the moment they're pressed or a new
direction starts. Both are on by default — disable per-widget with
`hapticFeedback: false` on `OnScreenControls`/`VirtualButton`/
`VirtualJoystick`.

The joystick reports only discrete `"left"`/`"right"`/`"up"`/`"down"`
by default. Pass `analogOutput: true` (on `OnScreenControls` or
`VirtualJoystick` directly) to also get continuous displacement on
`InputState.axis('moveX')`/`axis('moveY')` (range -1..1) — useful for
variable-speed movement or analog aiming instead of fixed-speed
digital movement. Axis values reset to `0` on release. Existing
systems that only read `isPressed(...)` are unaffected either way.

```dart
final speed = baseSpeed * inputState.axis('moveX').abs().clamp(0.3, 1.0);
```

## Parallax backgrounds

```dart
final sky = world.spawn();
world.storeOf<Position>().set(sky, Position(0, 0));
world.storeOf<ParallaxLayer>().set(sky, ParallaxLayer('bg', 'sky', scrollFactorX: 0.2));

final mountains = world.spawn();
world.storeOf<Position>().set(mountains, Position(0, 40));
world.storeOf<ParallaxLayer>().set(mountains, ParallaxLayer('bg', 'mountains', scrollFactorX: 0.5));
```

`ParallaxLayer` is an atlas region (same `atlasId`/`region` idea as
`Sprite`) that scrolls at `scrollFactorX`/`scrollFactorY` — the
fraction of camera movement it tracks: `0` stays fixed to the screen,
`1` scrolls exactly like normal world content, anything in between
reads as "further away." `EngineView` draws every layer first, behind
tiles/sprites/particles. `tileX`/`tileY` (default `tileX: true`) repeat
the region across the whole viewport so one authored strip covers
arbitrarily wide scrolling — turn either off for a layer meant to
appear once (a fixed logo, say) instead of tiled.

## Particle effects

```dart
final emitter = world.spawn();
world.storeOf<Position>().set(emitter, Position(playerX, playerY));
world.storeOf<ParticleEmitter>().set(emitter, ParticleEmitter(
  burstCount: 20,          // one-shot -- set again for another burst
  speedMin: 60, speedMax: 160,
  lifetimeMin: 0.3, lifetimeMax: 0.6,
  colorArgb: 0xFFFFAA33,
));
```

`ParticleEmitter`/`Particle`/`ParticleSystem` live in `engine_core`
(genre-general, pure Dart — `colorArgb` is a plain int rather than a
Flutter `Color` so this stays usable with no Flutter dependency).
Register `ParticleSystem()` alongside `MovementSystem()` — spawned
particles get `Position`/`Velocity` from the emitter's origin and rely
on `MovementSystem` to actually move, not a separate step. Set
`emitter.rate` instead of/alongside `burstCount` for continuous
emission (a torch, a waterfall). `EngineView` draws every `Particle` on
top of sprites: a particle with its own `Sprite` component renders that
region scaled by `Particle.scale`, otherwise a plain circle in
`Particle.colorArgb` — both fade via `Particle.alpha` as the particle
ages toward its lifetime.

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
