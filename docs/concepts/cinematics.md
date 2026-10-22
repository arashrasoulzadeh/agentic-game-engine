# Cinematics and scene transitions

Three tools, from smallest to largest: a **cinematic** scripts a sequence inside a scene, a **scene transition**
covers and reveals the swap between scenes, and a **video** plays a pre-rendered clip. The cinematic samples are
executed by `packages/engine_core/test/doc_examples_cinematics_test.dart`.

## Cinematics: a script of steps

A `CinematicSystem` plays `CinematicStep`s one after another. It is an ordinary system, so it works for a full
cutscene scene or a beat in a playable level (a door opening, a boss intro).

```dart
final events = <String>[];
world.events.on<CinematicCompleteEvent>((_) => events.add('done'));

final cinematic = CinematicSystem([
  CallbackStep((w) => events.add('show line')),   // a one-off effect
  WaitStep(1.5),                                   // a beat
  TweenStep(                                       // drive any value 0 -> 1
    duration: 2,
    easing: EasingType.easeInOutQuad,
    onUpdate: (w, t) => events.add('t=${t.toStringAsFixed(1)}'),
  ),
  SetFlagStep(flag: 'intro_seen'),                 // remember it happened
]);
world.addSystem(cinematic);
```

Built-in steps: `WaitStep`, `CallbackStep`, `TweenStep`, `MoveCameraStep`, `FollowEntityStep`, `SpawnEntityStep`,
`PlaySoundStep`, `SetFlagStep`. Write your own by extending `CinematicStep` (`start`, `update`, `skip`).

- **Input control** is yours: check `cinematic.isPlaying` where your game reads input, and resume on
  `CinematicCompleteEvent`.
- **Skipping:** `cinematic.skip(world)` calls each remaining step's `skip`, which must leave the world in that
  step's *end* state (a tween jumps to its final value, a dialogue line simply never shows), then completes.
- `addStep` extends a cinematic that is still playing (once it has completed it stays done).

## Scene transitions

`GameRunner` swaps scenes with `SceneController.loadSceneWithTransition(next, config)`. A transition plays in two
phases of `duration` seconds each: cover the outgoing scene, swap, reveal the new one.

```dart
const config = SceneTransitionConfig(
  type: SceneTransitionType.fade,   // fade | iris | crossfade | slideLeft/Right/Up/Down | pixelDissolve
  duration: 0.6,
  easing: EasingType.easeInOutQuad,
  fadeColorArgb: 0xFF000000,        // the colour a fade goes through
);
sceneController.loadSceneWithTransition(NextScene(), config);
```

`fade` and `iris` are drawn by screen-tint and clip components; the slide, crossfade and dissolve types draw a
snapshot of the outgoing scene on top of the new one. A `null` config swaps immediately. The config is JSON
(`toJson` / `fromJson`) so a level or scene file can name its own transition.

## Video

`VideoPlayer('assets/cutscenes/intro.mp4')` plays a pre-rendered clip (`initialize`, `play`, `pause`); the file must
be listed as a Flutter asset. Use a video for what the engine cannot draw; use a cinematic when the sequence
should react to the game's state or be skippable honestly.
