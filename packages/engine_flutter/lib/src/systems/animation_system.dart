import 'package:engine_core/engine_core.dart';

import '../components/animation.dart';
import '../components/sprite.dart';

/// Advances each entity's `AnimationState` by `dt` and writes the current
/// frame's region name onto its `Sprite`. Lives in engine_flutter (not
/// engine_core) because it operates on Sprite/AnimationState, which are
/// themselves Flutter-adjacent (atlas-based) components.
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

      state.elapsed += dt;
      while (state.elapsed >= clip.frameDurationSeconds) {
        state.elapsed -= clip.frameDurationSeconds;
        final nextIndex = state.frameIndex + 1;
        if (nextIndex >= clip.frameRegions.length) {
          if (clip.loop) {
            state.frameIndex = 0;
          } else {
            state.frameIndex = clip.frameRegions.length - 1;
            state.playing = false;
            break;
          }
        } else {
          state.frameIndex = nextIndex;
        }
      }

      sprite.region = clip.frameRegions[state.frameIndex];
    }
  }
}
