# Rendering (`engine_flutter`)

Everything under `packages/engine_flutter/lib/src/rendering/` and
`logic/`. This package is the Flutter shell around `engine_core`'s
simulation — it draws what the `World` contains; it never contains
gameplay logic itself.

## The pipeline: `Game` → `Scene` → `EngineView`

- `Game` (`logic/game.dart`) — your app's entry point. Implement
  `config`, `createInitialScene()`; override `createInputController()`,
  `cameraFollowEntity()`, etc. as needed. Pass an instance to `runGame()`.
- `Scene` (`logic/scene.dart`) — one level/room. `GameRunner` builds a
  fresh `World` per scene, registers components, then calls
  `populate(world, scenes, state)` → `loadAssets()` → `createCamera(world)`
  in that order.
- `EngineView` — the actual `CustomPaint`/render loop; you don't touch
  it directly in normal usage, `GameRunner` owns it.

## `Sprite`: data-only, resolved against an `AtlasRegistry`

A `Sprite` component (`rendering/sprite.dart`) is just `{atlasId,
region, rotation, scaleX, scaleY, screenSpace}` — plain JSON, resolved
against a loaded `AtlasRegistry` at render time, not a live `Image`
reference. This is what keeps it agent-authorable content, same as
every other component.

```dart
world.storeOf<Sprite>().set(id, Sprite('characters', 'player_idle'));
```

`screenSpace` (default `false`) switches a sprite between world space
(scrolls/zooms with `Camera`, the default) and screen space (fixed
viewport pixels, for UI decoration like menu frames/icons) — `Text`
and `HudBar` have the same flag with the *opposite* default (`HudBar`
defaults `true`/screen space, since a HUD bar pinned to the viewport
was the only case that motivated it).

Load atlases in `Scene.loadAssets()`:

```dart
@override
Future<AtlasRegistry> loadAssets() async {
  final registry = AtlasRegistry();
  registry.register('characters', await SpriteAtlas.loadFromAssets(
    imageAssetPath: 'assets/characters.png',
    manifestAssetPath: 'assets/characters.json',
  ));
  return registry;
}
```

Sprites batch through `Canvas.drawAtlas` per z-index — see
`packages/engine_flutter/README.md` for the packing tool
(`game_agent pack-assets`) that produces the manifest.

## Camera

`Camera` (`rendering/camera.dart`) is `{x, y, zoom}` plus screen-shake
state (`shake(magnitude, duration)`). `Scene.createCamera(world)`
returns the starting camera (default: centered on the world);
`Game.cameraFollowEntity(world)` returns an `EntityId` to re-center on
every frame instead of a fixed point.

## Text and HudBar

`Text` (world- or screen-space, single/multi-line) and `HudBar` (a
filled rectangle meter — health/stamina/boss bars) are drawn fresh
every frame from their component data — "doesn't hide how it works"
primitives, same philosophy as `Sprite`. Neither updates its own
`value`/`text` — sync them yourself each tick from wherever the real
number lives (e.g. `engine_platformer`'s `Health` via
`HealthHudSystem`/`HealthHudLink`, see
[platformer.md](platformer.md)).

Right-to-left text (Persian, Arabic): `Text` follows the active locale's direction; set `Text.rtl` (`true` /
`false`, default `null` = locale) to force it for one line, e.g. a Persian lore line inside an English UI.
Wrapped lines (`maxWidth`) follow the component's `align` inside their box.

## Lighting: `Light2D`

2D lighting with soft falloff, color tint, real shadow casting (CPU
raycast against `TileMap` by default; opt-in, currently-unsafe-on-some-
devices GPU-shader shadows via `Light2D.useGpuShadows` — see
[TODO.md](../../TODO.md) for the known issue, don't enable it), cone/
flashlight mode, flicker, and a day/night ambient cycle
(`DayNightCycle` in `engine_core`, since it's genre-general timeline
data, not rendering-specific). `GameConfig.ambientBrightness < 1.0`
darkens the whole scene, revealed again through each `Light2D` entity.

## Aspect ratio and safe areas

`EngineView(viewportConfig: ViewportConfig(...))` decides the **rectangle** the game is drawn in on screens of
any shape; by default it does not scale the world (one world unit is still `Camera.zoom` pixels).

```dart
EngineView(
  // ...
  viewportConfig: const ViewportConfig(
    targetAspectRatio: 16 / 9,
    fit: ViewportFit.contain,        // contain | cover | width | height
    letterboxColorArgb: 0xFF000000,  // the bars
  ),
)
```

| `fit` | Result |
|---|---|
| `contain` | Largest 16:9 area that fits; bars fill the rest. Nothing cropped. |
| `cover` | Smallest 16:9 area that covers the screen. No bars; the overflow is cropped. |
| `width` / `height` | Spans the screen's width / height; bars or cropping on the other axis. |

With `avoidSystemUi` (default) the area stays inside the system safe area (notches, status and navigation
bars). A screen that already has the target ratio gets exactly the whole screen and no bars. Taps
(`onWorldTap`) and camera-follow clamping use the drawn area's own size and origin, so a tap in a bar is
simply outside the game. To keep a fixed field of view on every screen, choose `Camera.zoom` from the
screen size yourself, or set `fitWorld: true` and the engine does it: every frame it sets `Camera.zoom` so the
whole world width fills the drawn area. A 180x320 portrait game is
`ViewportConfig.fittingWorld(180, 320)` (what `Game.viewportConfig` returns: that aspect ratio, letterboxed, scaled,
ignoring system insets) and needs no zoom maths of its own. Fullscreen/immersive mode is `GameConfig.fullscreen`
(`"fullscreen": true` in `game_config.json`); `runGame(game)` is the whole `main`. Tested in `packages/engine_flutter/test/viewport_test.dart`.

## Animation

`AnimationClip`/`AnimationState` + `AnimationSystem` drive sprite-frame
playback from component data; `AnimationTransitionSystem` crossfades
between clips. `engine_platformer`'s `MovementAnimationSet`/
`JumpAnimationSet` (see [platformer.md](platformer.md)) are the
platformer-specific layer that decides *which* clip should be playing
from movement state — this package only plays whatever clip it's told.

### Sheets with a sidecar

`loadSpriteSheet('assets/hero/hero_idle')` loads `hero_idle.png` as a strip atlas laid out by its sidecar
`hero_idle.json` (`cell`, `gap`, `frames`; frame `i` is the `cell`-sized square at `x = gap + i * (cell + gap)`,
regions `'0'..'frames-1'`) and measures each frame's feet (below). `loadFxClip` reads an effect sheet's frame count the
same way. Art plus a tiny JSON, no cell sizes in code.

### Sprite states

Hand-painted characters usually ship one sheet per state. `SpriteStates` holds a clip per state (`idle`, `attack`,
`death`, ...), each with its own `atlasId`, frame count, pace and optional `frameEvents`. Ask for a state with
`playSpriteState(world, entity, 'attack')`; `SpriteStateSystem` (register before `AnimationSystem`) swaps the sprite's
atlas and clip, sends a finished one-shot back to `restState` (`idle`) and freezes `holdStates` (default `death`) on
their last frame. `spriteStateFinished(world, entity, 'death')` says when a clip has played out. A clip's
`frameEvents` ride on the playing `AnimationClip`, so `installAnimationCueSystems` fires camera shake, particle bursts
and sfx on that frame.

### Feet pivots

Sheets are cropped per pose, so drawing each frame centred makes a character slide and bob. `sheetPivots` measures
each frame's feet from the pixels (lowest opaque row; X from the bottom of the silhouette, not the bounding box a
spear would skew); `loadSpriteSheet` does it for you into a `PivotTable`. `SpritePivotSystem(table)` (register right
after `AnimationSystem`) offsets every `SpriteStates` sprite so its feet stay where its `idle` frame 0 stands, across
frames and states. This replaces hand-authoring `AnimationClip.frameOffsets`.

### One-shot effects

`spawnFx(world, FxClip('fx_spark', 5), x: ..., y: ..., scale: ...)` plays an effect sheet once, centred at a point;
`OneShotFxSystem` (after `AnimationSystem`) removes it when the clip ends.

### Parallax scrolling

`ParallaxScroller.spawn(world, 'bg', [ParallaxSpec('far', 0.3), ParallaxSpec('ground', 1.0), ...])` creates tiled
`ParallaxLayer`s (atlas `bg_<name>`); `scroller.scroll(world, distance)` moves each by `distance x speed` through
`Position`. For a hero who stays put on screen (idle and auto-walk games) the camera and HUD never move.

## Debug overlays

`GameConfig.showColliderDebug`/`showPerformanceOverlay`/`showFpsOverlay`
— all forced off in release builds regardless of a shipped
`game_config.json` (a deliberate safety net, not a bug — see the
"Force debug overlays off in release builds" commit). `FrameStats.onSpike`
fires the instant a frame exceeds a threshold, for chasing a specific
perf report without a full profiler session.

## See also

- [platformer.md](platformer.md) — the genre-specific layer built on top of this.
- [`packages/engine_flutter/README.md`](../../packages/engine_flutter/README.md) — full API reference (input, audio, save/load, on-screen controls, menus).
