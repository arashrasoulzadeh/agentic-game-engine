import 'package:engine_core/engine_core.dart';

import 'animation.dart';

/// Requests a [ParticleEmitter] burst for [AnimationFrameEvent] cues with
/// `type == 'particle'`.
///
/// Call [attach] once on the world that runs [AnimationSystem]. The
/// emitting entity must already carry a [ParticleEmitter] (tune rate /
/// colors / shape at spawn); this only bumps [ParticleEmitter.burstCount]
/// so `ParticleSystem` fires on the next tick. [update] is a no-op.
///
/// Cue payload (in [AnimationEvent.data]):
/// - `count` — particles to burst (default `8`)
class AnimationParticleSystem implements System {
  bool _attached = false;

  @override
  String get name => 'animationParticle';

  /// Registers the frame-event handler on [world]. Safe to call more than
  /// once — subsequent calls are no-ops.
  void attach(World world) {
    if (_attached) return;
    _attached = true;
    world.events.on<AnimationFrameEvent>((event) {
      if (event.type != 'particle') return;
      final emitter = world.storeOf<ParticleEmitter>().get(event.entity);
      if (emitter == null) return;
      final count = (event.data['count'] as num?)?.toInt() ?? 8;
      if (count <= 0) return;
      emitter.burstCount += count;
    });
  }

  @override
  void update(World world, double dt) {
    // Event-driven — see [attach].
  }
}
