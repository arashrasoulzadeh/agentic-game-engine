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

## Quick start: `Game` + `Scene`

This is the intended way to build a game — extend `Game`, implement one
or more `Scene`s (a `Scene` is one level/room), call `runGame`. `Game`
itself only configures the app and picks the first `Scene`; each
`Scene` owns populating its own `World`, loading its own assets, and
its own starting camera:

```dart
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Velocity, Text;

Future<void> main() async {
  runGame(MyGame());
}

class MyGame extends Game {
  @override
  GameConfig get config => const GameConfig(worldWidth: 800, worldHeight: 600);

  @override
  Scene createInitialScene() => MainScene();
}

class MainScene extends Scene {
  @override
  Future<void> populate(
    World world, SceneController scenes, GameState state,
  ) async {
    // GameRunner already built `world` (sized from config) and called
    // registerCoreComponents/registerFlutterComponents for you — just
    // add your own systems and spawn entities.
    world.addSystem(MovementSystem());
    world.addSystem(CollisionSystem());
    // ...
  }
}
```

`Game` has optional overrides you'll commonly want:

| Method | Default | Override for |
|---|---|---|
| `createInitialScene()` | (required) | The first `Scene` `GameRunner` loads |
| `createInitialState()` | empty `GameState` | Seeding starting values (coins collected, etc.) that survive scene switches |
| `createInputController()` | `null` (no keyboard/touch input) | Custom key bindings — also drives on-screen touch controls, see below |
| `cameraFollowEntity(world)` | `null` (static camera) | Camera-follow target (usually the player) |
| `onPause()` / `onResume()` | no-op | Save-on-pause, pausing audio, etc. |
| `onScreenButtons()` | one `"jump"` button | Which touch buttons to show and what action each sets |
| `onScreenJoystickVertical` | `false` | Set `true` if the joystick should also drive `"up"`/`"down"` (top-down games) |

`Scene` has its own overrides:

| Method | Default | Override for |
|---|---|---|
| `populate(world, scenes, state)` | (required) | Adding systems, spawning entities |
| `loadAssets()` | empty `AtlasRegistry` | Loading sprite atlases before the first frame |
| `createCamera(world)` | centered on the world | Starting camera position/zoom for this scene |

A game with rooms/doors implements one `Scene` per room and calls
`scenes.loadScene(NextRoomScene())` from inside `populate` (typically
from a collision handler) to switch — `GameRunner` always builds a
fresh `World` for the new scene, but the `GameState` your `Game`
created is passed through unchanged, so it's the one place to stash
anything that must survive the switch.

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
  "onScreenControls": "auto",
  "maxFps": 60
}
```

`maxFps` (`null` default — uncapped, runs at whatever the platform's raw
display callback delivers) caps how often the world steps/repaints — a
ceiling on frequency, not a guaranteed rate on a device that can't reach
it. Schedules against a virtual clock advancing by a fixed `1 / maxFps`
each processed frame rather than the last raw callback's own timestamp,
so a refresh rate that isn't an exact multiple of the cap (90Hz capped
to 60fps, say) still gets a clean, consistent rate instead of
alternating gaps.

`showFpsOverlay` shows a top-left debug panel (not just fps despite the
name): fps, tick count, live entity/sprite/particle counts, and
resident memory where available (not on web — `dart:io` has no memory
API there, so that line is simply omitted).

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

**Crossfading between clips**: set `AnimationState.crossfadeSeconds` (`0`
default — an instant cut) on an entity, and the next time its clip
changes, the outgoing frame fades out as a transient `AnimationTransition`
(add `AnimationTransitionSystem()` to actually count it down/remove it)
instead of popping instantly to the new one. Frozen-frame, not fully
animated — the outgoing clip doesn't keep playing during the fade, it's
just the one frame it was on, fading to transparent.

**Resizable UI panels**: `NineSliceSprite(atlasId, region, width:, height:,
insetLeft:, insetTop:, insetRight:, insetBottom:)` splits one atlas
region into a 3x3 grid — corners drawn at native size, edges stretch
along one axis, the center stretches both — so a dialog-box/panel
background can resize to any `width`/`height` without its border art
stretching into mush the way a plain scaled `Sprite` would. Always
screen-space (`Position` is viewport pixels, ignoring the camera), same
as `HudBar`.

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
player entity in `Scene.populate` (`engine_platformer`'s `spawnPlayer`
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

## Draw order (z-index)

Every renderable — `Sprite`, `ParallaxLayer`, `TileMap`, `Particle`
(`Particle.zIndex` comes from the `ParticleEmitter.zIndex` that spawned
it) — has a `zIndex` (an `int`, default `0`). `EngineView` draws lower
`zIndex` first (further back) and higher last (further forward),
regardless of which kind of renderable it is:

```dart
world.storeOf<Sprite>().set(id, Sprite('atlas', 'idle', zIndex: 10)); // draws in front of...
world.storeOf<ParallaxLayer>().set(bg, ParallaxLayer('atlas', 'sky', zIndex: -10)); // ...this
```

Ties (the common case: everything left at the default `0`) fall back to
the engine's original fixed order — parallax, then tiles, then sprites,
then particles, each in `ComponentStore` order — so a game that never
sets `zIndex` renders exactly as before this existed. Use it for a
foreground mask/overhang `TileMap` layer drawn above characters, a
sprite that should always render in front of/behind everything else,
or reordering parallax layers relative to gameplay content.

Sprite batching (see below) still applies *within* a `zIndex` — sprites
sharing both a `zIndex` and an atlas batch into one `Canvas.drawAtlas`
call; different `zIndex` values always mean separate draw calls, since
they can't be interleaved with other kinds' draws otherwise.

Note: this orders *draw calls*, not alpha compositing — two overlapping
opaque sprites at different `zIndex` behave as you'd expect (the higher
one fully covers the lower one where they overlap), but z-index alone
can't say "this shape cuts a hole in what's behind it" or "only show
the scene through this shape" — see `ClipShape` below for that.

## Masking/clipping (`ClipShape`)

```dart
final spotlight = world.spawn();
world.storeOf<Position>().set(spotlight, Position(playerX, playerY));
world.storeOf<ClipShape>().set(spotlight, ClipShape(radius: 80)); // reveal (default)

final vignette = world.spawn();
world.storeOf<Position>().set(vignette, Position(viewportCenterX, viewportCenterY));
world.storeOf<ClipShape>().set(
    vignette, ClipShape(radius: 400, mode: ClipShapeMode.cutout, softness: 40));
```

Circle (`isCircle: true`, the default, sized by `radius`) or rect
(`width`/`height`), centered on the entity's own `Position`.
`ClipShapeMode.reveal` (the default) shows the scene *only* where at
least one reveal shape covers it — a hard-edged spotlight/peephole, or
a growing/shrinking wipe transition; `ClipShapeMode.cutout` does the
opposite, punching a hole through the already-drawn scene wherever it
covers, showing nothing there at all — a vignette is a cutout shape
sized to the screen's edges with the visible area left uncovered in
the middle. `softness` (`0` default, hard edge) blurs the shape's
boundary, same convention as `Light2D.shadowEdgeSoftness` below. Zero
cost when no `ClipShape` of a given mode exists in the world.

## Lighting (`Light2D`)

```dart
final torch = world.spawn();
world.storeOf<Position>().set(torch, Position(torchX, torchY));
world.storeOf<Light2D>().set(torch, Light2D(
  radius: 160,
  intensity: 0.9,
  colorArgb: 0x88FF8800,   // warm orange tint; alpha is tint strength
  castsShadows: true,       // TileMap walls actually block this light
  flickerSpeed: 3, flickerAmount: 0.15, // gentle guttering
));
```

Set `EngineView(ambientBrightness: 0.15)` (default `1.0` — no
darkening at all, zero extra cost) to darken the whole scene and let
`Light2D` entities reveal it back in a circle/cone around themselves.
Everything below is opt-in and off by default — a plain `Light2D()`
behaves exactly like the very first version of this component:

- **`castsShadows`** (`false` default): samples `shadowRayCount` (`48`
  default) rays via `raycastTileMap` — the same primitive AI line-of-
  sight uses — to build a real visibility polygon, so `TileMap` walls
  actually block light instead of it shining straight through them.
  `blockOneWayPlatforms` (`false` default) additionally makes one-way
  platforms opaque to light, matching how they *look* even though they
  don't collide from below.
- **`coneAngle`/`coneDirection`** (`null`/`0` default — full 360°
  point light): a flashlight/directional beam instead, composing for
  free with `castsShadows` since both go through the same polygon code.
- **`colorArgb`** (`0x00FFFFFF` default — transparent, no tint pass at
  all): an additive color tint layered on top of the brightness reveal,
  strongest at the center. **`overbrightIntensity`** (`0` default) is a
  separate, independent additive white glow — unlike the brightness
  reveal alone (which can only ever erase darkness back to "fully
  revealed," never past it), this genuinely stacks brighter where two
  lights overlap.
- **`flickerSpeed`/`flickerAmount`** (`0`/`0.3` default): a
  `LightFlickerSystem` (add it once per `World`) oscillates
  `intensity`/`radius` around `baseIntensity`/`baseRadius` for a
  guttering torch/failing-bulb effect.
- **`minZIndex`/`maxZIndex`** (`null` default — affects every
  `zIndex`): scopes a light to one z-band, so a ground-level torch
  doesn't dim/reveal a foreground overlay or background parallax layer
  sitting at a different `zIndex`.
- **`openAirFalloffScale`** (`1.0` default — no shrink): only with
  `castsShadows` on, a ray that travels its *entire* radius
  unobstructed (open sky above an outdoor level, say) is pulled in to
  `radius * openAirFalloffScale` instead of reaching the full radius —
  a ray that hits a real surface short of the radius is always left
  untouched, so the light still fully illuminates whatever it's
  actually next to.
- **`shadowEdgeSoftness`**/**`shadowSmoothingSeconds`**/
  **`cacheShadowGeometry`**: cosmetic/perf knobs for a shadow-casting
  light's polygon — blurred edges, smoothed per-ray distances for a
  moving light (reads as the shadow lagging into place — off by
  default for exactly that reason), and reusing last frame's raycast
  sweep for a light that hasn't moved, respectively.

`EngineView` also viewport-culls a light whose screen-space circle
never reaches the visible rect before doing any of the expensive
per-ray work.

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
constructed `World`, not one `Scene.populate` has already filled.
Multiple save slots via the `slot` parameter.

**Schema versioning**: pass `version:` (default `1`) to `save`/`load` —
bump it whenever a save-affecting shape changes (a component's fields,
which components a save cares about). A mismatched save throws
`SaveVersionException` unless you pass a `migrate` callback to `load`,
which receives the raw saved world JSON and the version it was written
at, and returns JSON patched up to the current version. A save written
before versioning existed has no envelope at all and is treated as
version `1`.

## Camera

```dart
final camera = Camera(x: 0, y: 0, zoom: 1);
camera.follow(playerX, playerY, viewportSize: size, worldWidth: w, worldHeight: h);
```

`follow` clamps so the viewport never shows past world bounds (unless
the world is smaller than the viewport, in which case it just centers).

## Fixed timestep

```dart
EngineView(world: world, atlasRegistry: registry, camera: camera,
    fixedTimestepSeconds: 1 / 60)
```

`null` (default) steps `world.step(dt)` once per rendered frame with
whatever `dt` that frame actually took — simple, but ties simulation
determinism to the display's refresh rate. Set `fixedTimestepSeconds`
to instead accumulate real elapsed time and run `world.step` in fixed-
size chunks (capped at 5 catch-up steps per rendered frame — a slow
frame drops the backlog rather than spiraling into more and more
simulation work). Rendered `Sprite`/`Particle`/`Light2D` positions are
smoothly interpolated between the last two simulated states using the
leftover fractional accumulator, so motion still reads smoothly on a
display faster than the fixed step, instead of visibly stepping.

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
