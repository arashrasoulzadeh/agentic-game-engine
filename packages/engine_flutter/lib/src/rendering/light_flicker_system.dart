import 'dart:math';

import 'package:engine_core/engine_core.dart';

import 'light2d.dart';

/// Varies `Light2D.intensity`/`.radius` around `.baseIntensity`/
/// `.baseRadius` for lights with `flickerSpeed > 0` — a torch guttering,
/// a failing warning light. A no-op (and near-zero cost — one
/// comparison) for any light with `flickerSpeed == 0`, the default, so
/// installing this system doesn't change anything for a game that
/// hasn't opted into flicker.
///
/// Uses two layered sine waves at different frequencies/phases rather
/// than real randomness — smoother frame-to-frame than raw noise would
/// be without needing a stored `Random` per light (which would also
/// need its own seed to survive `toJson`/`fromJson` round-trips
/// deterministically); "deterministic pseudo-flicker" reads as organic
/// enough for this effect and keeps `Light2D` plain, seedless data.
class LightFlickerSystem implements System {
  @override
  String get name => 'lightFlicker';

  @override
  void update(World world, double dt) {
    final lights = world.storeOf<Light2D>();
    for (var i = 0; i < lights.length; i++) {
      final light = lights.denseAt(i);
      if (light.flickerSpeed <= 0) continue;

      light.flickerElapsed += dt;
      final t = light.flickerElapsed * light.flickerSpeed;
      final noise = sin(t * 2 * pi) * 0.6 + sin(t * 2.7 * pi + 1.3) * 0.4;
      final factor = 1 + noise * light.flickerAmount;

      light.intensity = (light.baseIntensity * factor).clamp(0, 1);
      light.radius = (light.baseRadius * factor).clamp(0, double.infinity);
    }
  }
}
