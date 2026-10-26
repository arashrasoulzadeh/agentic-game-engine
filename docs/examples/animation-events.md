# Recipe: animation frame events (SFX, hitbox, shake, particles)

Attach cues to individual frames of an `AnimationClip`. `AnimationSystem`
emits an `AnimationFrameEvent` when playback enters that frame (including
the starting frame of a freshly attached clip). Bridge systems turn the
opaque `type` / `data` into gameplay.

```dart
final attack = AnimationClip(
  'attack',
  ['atk_0', 'atk_1', 'atk_2', 'atk_3'],
  frameDurationSeconds: 0.06,
  loop: false,
  frameEvents: [
    [],
    [AnimationEvent('sfx', {'id': 'swing'})],
    [
      AnimationEvent('hitbox_on'),
      AnimationEvent('shake', {'magnitude': 3, 'duration': 0.12, 'impulse': true}),
      AnimationEvent('particle', {'count': 10}),
    ],
    [AnimationEvent('hitbox_off')],
  ],
);

world.storeOf<AnimationState>().set(player, AnimationState(attack));
world.storeOf<ParticleEmitter>().set(player, ParticleEmitter()); // for particle cues
world.addSystem(AnimationSystem());

final sfx = AnimationSfxSystem(audio, soundIds: {'swing': 'sfx/sword.wav'});
sfx.attach(world);
world.addSystem(sfx);

final shake = AnimationShakeSystem(camera)..attach(world);
world.addSystem(shake);

final particles = AnimationParticleSystem()..attach(world);
world.addSystem(particles);

// Melee that opens only during hitbox_on … hitbox_off:
world.storeOf<Weapon>().set(
  player,
  Weapon(kind: WeaponKind.melee, meleeHitboxFromAnimation: true),
);
```

## Cue types the engine bridges

| `type` | Bridge | `data` |
|---|---|---|
| `sfx` | `AnimationSfxSystem` | `id` or `asset`, optional `volume` |
| `hitbox_on` / `hitbox_off` | `AttackSystem` when `Weapon.meleeHitboxFromAnimation` | (none) |
| `shake` | `AnimationShakeSystem` | `magnitude` (required), `duration`, `frequency`, `impulse`, `axis`, `stack` |
| `particle` | `AnimationParticleSystem` | `count` (default 8); entity needs a `ParticleEmitter` |

Anything else is fair game — subscribe with
`world.events.on<AnimationFrameEvent>(...)` in game code.

## Dialogue audio (related)

`DialogueRunner.advance` emits `DialoguePlaySoundEvent` for choice SFX
and next-node VO. Wire the same way:

```dart
final dialogueSfx = DialogueSfxSystem(audio, soundIds: {
  'ui.click': 'sfx/ui_click.wav',
});
dialogueSfx.attach(world);
```

See `packages/engine_flutter/lib/src/audio/animation_sfx_system.dart`
and the proposal at
[docs/proposals/animation-events-and-ide.md](../proposals/animation-events-and-ide.md).
