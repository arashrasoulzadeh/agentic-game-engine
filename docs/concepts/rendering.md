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

## Lighting: `Light2D`

2D lighting with soft falloff, color tint, real shadow casting (CPU
raycast against `TileMap` by default; opt-in, currently-unsafe-on-some-
devices GPU-shader shadows via `Light2D.useGpuShadows` — see
[TODO.md](../../TODO.md) for the known issue, don't enable it), cone/
flashlight mode, flicker, and a day/night ambient cycle
(`DayNightCycle` in `engine_core`, since it's genre-general timeline
data, not rendering-specific). `GameConfig.ambientBrightness < 1.0`
darkens the whole scene, revealed again through each `Light2D` entity.

## Animation

`AnimationClip`/`AnimationState` + `AnimationSystem` drive sprite-frame
playback from component data; `AnimationTransitionSystem` crossfades
between clips. `engine_platformer`'s `MovementAnimationSet`/
`JumpAnimationSet` (see [platformer.md](platformer.md)) are the
platformer-specific layer that decides *which* clip should be playing
from movement state — this package only plays whatever clip it's told.

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
