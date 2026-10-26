import 'package:engine_core/engine_core.dart';

import 'animation.dart';
import 'camera.dart';

/// Triggers [Camera.shake] for [AnimationFrameEvent] cues with
/// `type == 'shake'`.
///
/// Call [attach] once on the world that runs [AnimationSystem]. [update]
/// is a no-op — playback is event-driven.
///
/// Cue payload (in [AnimationEvent.data]):
/// - `magnitude` — world units (required; ignored if missing/≤0)
/// - `duration` — seconds (default `0.15`)
/// - `frequency` — default `1.0`
/// - `decay` — default `1.0`
/// - `impulse` — default `false`
/// - `axis` — `"x"` / `"y"` / `"both"` (default both)
/// - `stack` — default `false`
class AnimationShakeSystem implements System {
  final Camera camera;

  bool _attached = false;

  AnimationShakeSystem(this.camera);

  @override
  String get name => 'animationShake';

  /// Registers the frame-event handler on [world]. Safe to call more than
  /// once — subsequent calls are no-ops.
  void attach(World world) {
    if (_attached) return;
    _attached = true;
    world.events.on<AnimationFrameEvent>((event) {
      if (event.type != 'shake') return;
      final magnitude = (event.data['magnitude'] as num?)?.toDouble();
      if (magnitude == null || magnitude <= 0) return;

      final duration = (event.data['duration'] as num?)?.toDouble() ?? 0.15;
      final frequency = (event.data['frequency'] as num?)?.toDouble() ?? 1.0;
      final decay = (event.data['decay'] as num?)?.toDouble() ?? 1.0;
      final impulse = event.data['impulse'] as bool? ?? false;
      final stack = event.data['stack'] as bool? ?? false;
      final axis = switch (event.data['axis'] as String?) {
        'x' => ShakeAxis.x,
        'y' => ShakeAxis.y,
        _ => ShakeAxis.both,
      };

      camera.shake(
        magnitude: magnitude,
        duration: duration,
        frequency: frequency,
        decay: decay,
        impulse: impulse,
        axis: axis,
        stack: stack,
      );
    });
  }

  @override
  void update(World world, double dt) {
    // Event-driven — see [attach].
  }
}
