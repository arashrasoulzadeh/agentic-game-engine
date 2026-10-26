import 'package:engine_core/engine_core.dart';

import 'animation.dart';
import 'sprite.dart';

/// Advances each entity's `AnimationState` by `dt` and writes the current
/// frame's region name — and, when the clip specifies one (see
/// `AnimationClip.frameOffsetsX`/`frameOffsetsY`), that frame's pivot
/// offset — onto its `Sprite`. When playback enters a frame that lists
/// cues in `AnimationClip.frameEvents`, emits one [AnimationFrameEvent]
/// per cue (opaque `type`/`data` — SFX/hitbox subscribers live elsewhere).
/// Lives in engine_flutter (not engine_core) because it operates on
/// Sprite/AnimationState, which are themselves Flutter-adjacent
/// (atlas-based) components.
///
/// "Enter" includes the first visit to a freshly attached
/// [AnimationState]'s starting [AnimationState.frameIndex] (so frame-0
/// cues fire without waiting for a loop), not only later advances.
class AnimationSystem implements System {
  @override
  String get name => 'animation';

  @override
  void update(World world, double dt) {
    final states = world.storeOf<AnimationState>();
    final sprites = world.storeOf<Sprite>();

    for (var i = 0; i < states.length; i++) {
      final entity = states.entityAt(i);
      final state = states.denseAt(i);
      final sprite = sprites.get(entity);
      if (sprite == null || !state.playing) continue;

      final clip = state.clip;
      if (clip.frameRegions.isEmpty) continue;

      if (state.lastEmittedFrameIndex != state.frameIndex) {
        _emitFrameEvents(world, entity, clip, state.frameIndex);
        state.lastEmittedFrameIndex = state.frameIndex;
      }

      state.elapsed += dt;
      while (state.elapsed >= clip.frameDurationSeconds) {
        state.elapsed -= clip.frameDurationSeconds;
        final nextIndex = state.frameIndex + 1;
        if (nextIndex >= clip.frameRegions.length) {
          if (clip.loop) {
            state.frameIndex = 0;
            _emitFrameEvents(world, entity, clip, 0);
            state.lastEmittedFrameIndex = 0;
          } else {
            state.frameIndex = clip.frameRegions.length - 1;
            state.playing = false;
            break;
          }
        } else {
          state.frameIndex = nextIndex;
          _emitFrameEvents(world, entity, clip, nextIndex);
          state.lastEmittedFrameIndex = nextIndex;
        }
      }

      sprite.region = clip.frameRegions[state.frameIndex];
      sprite.offsetX = clip.frameOffsetsX?[state.frameIndex] ?? 0;
      sprite.offsetY = clip.frameOffsetsY?[state.frameIndex] ?? 0;
    }
  }

  void _emitFrameEvents(
    World world,
    EntityId entity,
    AnimationClip clip,
    int frameIndex,
  ) {
    final events = clip.frameEvents?[frameIndex];
    if (events == null || events.isEmpty) return;
    for (final e in events) {
      world.events.emit(
        AnimationFrameEvent(
          entity,
          clip.name,
          e.type,
          e.data,
          frameIndex: frameIndex,
        ),
      );
    }
  }
}
