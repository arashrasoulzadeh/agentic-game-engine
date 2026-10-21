# Lighting

Lighting works by **darkening the whole scene and revealing it again through lights**. Set the ambient
brightness below 1, then give entities a `Light2D`; each light reveals the already-drawn scene around
it. Nothing is recoloured unless you ask for a tint.

Samples are executed by `packages/engine_core/test/doc_examples_day_night_test.dart` and
`packages/engine_flutter/test/doc_examples_lighting_test.dart`.

## Ambient darkness

```json
// assets/game_config.json
{ "ambientBrightness": 0.25 }
```

`1.0` is fully lit (no lighting pass); `0.0` is black except where lights reveal. A scene can override
it with `Scene.ambientBrightness` - a menu or HUD-only scene usually returns `1.0` so it is not darkened
along with gameplay.

## A light

`Light2D` is a component. Give it to an entity that has a `Position`:

```dart
world.storeOf<Position>().set(torch, Position(320, 200));
world.storeOf<Light2D>().set(torch, Light2D(radius: 120, intensity: 0.8));
```

| Field | Meaning |
|---|---|
| `radius` | World units the light reaches. |
| `intensity` | `0..1`: how fully it reveals the scene at its centre, falling off to 0 at the edge (full strength is held out to 60% of the radius, then fades). |
| `colorArgb` | Additive tint. **Alpha is the strength**; the default `0x00FFFFFF` has none and costs nothing. `0xAAFF6600` is a warm orange glow. |
| `coneAngle` / `coneDirection` | A flashlight beam instead of a circle: width and direction in radians (0 = right, increasing clockwise). |
| `overbrightIntensity` | Lets overlapping lights add up: two close torches brighten the ground between them beyond what either does alone. Small values (`0.1`-`0.25`). |

Everything beyond `radius` and `intensity` is opt-in, so a plain `Light2D()` is the cheap case.
It is plain data, so it serialises and can live in a level file like any component.

## Shadows

By default a light shines through walls. `castsShadows: true` casts rays out to `radius` and stops
each at the first solid `TileMap` tile, so walls block light.

- It costs one raycast per sampled angle per light per frame: enable it per light that is near
  walls, not globally. `shadowRayCount` (default 48) trades edge smoothness for cost.
- `shadowEdgeSoftness` (default 8) blurs the polygon edge; `0` is hard.
- `cacheShadowGeometry: true` reuses the result while the light has not changed - a large win for
  stationary lights.
- One-way platforms do not block light unless `blockOneWayPlatforms: true`.
- `shadowSmoothingSeconds` smooths the shadow edge for a moving light.

!!! danger "Do not enable `useGpuShadows`"
    `Light2D.useGpuShadows` draws the shadow with a fragment shader instead of the CPU raycast. It has
    a **known, unresolved bug on at least one real Android device** (the overlap of several lights
    saturating to white). A candidate fix is in place but unverified, so leave it `false`.
    See [`TODO.md`](https://github.com/arashrasoulzadeh/agentic-game-engine/blob/main/TODO.md).

## Flickering

A torch that gutters:

```dart
world.addSystem(LightFlickerSystem());
world.storeOf<Light2D>().set(
  torch,
  Light2D(radius: 120, intensity: 0.8, flickerSpeed: 3, flickerAmount: 0.3),
);
```

`LightFlickerSystem` moves `intensity` and `radius` around `baseIntensity` / `baseRadius` (they default
to the constructor values) by up to `flickerAmount`. Once a light flickers, change the **base** values,
not `intensity`/`radius`, which are overwritten every tick.

For a flickering light that **casts shadows**, set `flickerAffectsRadius: false`: the radius is part of
the shadow geometry and its cache key, so a flickering radius forces a fresh raycast every frame even for
a stationary light. With it off the radius stays put and `cacheShadowGeometry` can actually hit.

## Day and night

`DayNightCycle` (in `engine_core`, since a clock is not rendering) turns time of day and weather into an
ambient brightness and colour:

```dart
final sky = DayNightCycle(hour: 18, dayLengthSeconds: 600, weather: Weather.rain, weatherIntensity: 0.7);

// in a Scene:
@override
DayNightCycle? get dayNightCycle => sky;      // EngineView advances it every tick
```

- `hour` is 0..24 and wraps; `dayLengthSeconds` is how long a full day takes (0 freezes the clock).
- `ambientBrightness` is the time-of-day brightness times the weather's: `clear`, `overcast`, `rain`,
  `fog`, scaled by `weatherIntensity` (0..1). `ambientColorArgb` tints the scene dawn-orange, noon-white,
  night-blue, with weather mixing it toward grey.
- It **multiplies** with `Scene.ambientBrightness` rather than replacing it, so a scene's own tuned
  baseline stays a ceiling that the cycle only dims further.
- A menu scene leaves `dayNightCycle` null.

## Cost, in short

Plain circles are cheap. Shadow casting, cones and tints are the expensive options, and they are per
light. Profile with the [profiler](performance.md) and `GameConfig.showFpsOverlay` before adding more.
