# Tweens and particles

Both are ordinary components driven by a system, so they save, load, and replay like
everything else. Samples are executed by
`packages/engine_core/test/doc_examples_effects_test.dart`.

## Tweens

A `Tween` is a number moving from `from` to `to` over `duration` seconds, with an easing
curve (`linear`, `easeInQuad`, `easeOutQuad`, `easeInOutQuad`). It does not know what it is
animating: read `tween.value` wherever you want it (an alpha, a scale, a position) and
`TweenSystem` advances `elapsed` each step.

```dart
world.addSystem(TweenSystem());

final fade = world.spawn();
world.storeOf<Tween>().set(
  fade,
  Tween(from: 1, to: 0, duration: 2, easing: EasingType.easeOutQuad),
);

world.events.on<TweenCompleteEvent>((e) => print('${e.entity} finished'));
```

- A plain tween stops at `to` and emits `TweenCompleteEvent` **once**.
- `loop: true` restarts from `from`; `pingPong: true` reverses direction each cycle. Neither
  ever completes (`isComplete` stays false).
- `elapsed` is part of the component's JSON, so a saved game resumes mid-animation.

## Particles

A `ParticleEmitter` on an entity with a `Position` spawns `Particle` entities; `ParticleSystem`
emits, applies forces, ages and removes them.

```dart
world.addSystem(ParticleSystem(random: Random(1)));   // seed it for reproducible effects

final fire = world.spawn();
world.storeOf<Position>().set(fire, Position(100, 100));
world.storeOf<ParticleEmitter>().set(
  fire,
  ParticleEmitter(burstCount: 20, lifetimeMin: 0.5, lifetimeMax: 0.5),
);
```

- **`burstCount`** spawns that many particles on the next step and resets to 0 — set it
  again to fire another burst. **`rate`** spawns continuously, per second (fractions carry
  over, so 30/s at 60 fps is exactly one every other frame).
- Each particle gets a random speed, angle and lifetime within the emitter's `*Min`/`*Max`
  ranges, and its scale and alpha ramp from `start*` to `end*` over its life.
- `emissionShape` (`point`, `circle`, `rect`, `edge`) and its size fields choose where in the
  area particles start; `followEmitter` makes them move with the emitter.
- Pass a seeded `Random` to `ParticleSystem` when the effect must be identical on every run
  (tests, replays, lockstep multiplayer). The default is unseeded.
- Particles are entities: they appear in `world.toJson()` and count toward your entity
  total, so cap `rate` × lifetime.

`engine_flutter` draws them (`EngineView` renders particle entities with their scale and
alpha); the simulation side above needs no Flutter.

## Not covered here yet

Cinematics, scene transitions and video playback are documented in source only; see
`TODO.md`.
