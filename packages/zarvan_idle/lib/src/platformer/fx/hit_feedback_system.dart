import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' show ScreenTint, Sprite;

import 'hit_components.dart';

/// Plays out [HitRecoil]s (as a sprite x-offset) and [ScreenFlash]es.
class HitFeedbackSystem extends System {
  @override
  String get name => 'hitFeedback';

  @override
  void update(World world, double dt) {
    final recoils = world.componentsOf<HitRecoil>();
    final sprites = world.componentsOf<Sprite>();
    final ended = <EntityId>[];
    for (var i = 0; i < recoils.length; i++) {
      final id = recoils.entityAt(i);
      final r = recoils.denseAt(i);
      r.age += dt;
      final sprite = sprites.get(id);
      if (r.age >= r.life) {
        sprite?.offsetX = 0;
        ended.add(id);
      } else if (sprite != null) {
        // Fast kick out, eased return.
        final t = r.age / r.life;
        sprite.offsetX =
            r.direction * r.amplitude * math.sin(math.pi * math.pow(t, 0.6));
      }
    }
    for (final id in ended) {
      recoils.remove(id);
    }

    final windups = world.componentsOf<WindupTint>();
    final windupEnded = <EntityId>[];
    for (var i = 0; i < windups.length; i++) {
      final id = windups.entityAt(i);
      final w = windups.denseAt(i);
      w.remaining -= dt;
      if (w.remaining <= 0) {
        windupEnded.add(id);
        final sprite = sprites.get(id);
        if (sprite != null && sprite.tintArgb == w.tintArgb) {
          sprite.tintArgb = null;
        }
      }
    }
    for (final id in windupEnded) {
      windups.remove(id);
    }

    final flashes = world.componentsOf<ScreenFlash>();
    final tints = world.componentsOf<ScreenTint>();
    for (var i = 0; i < flashes.length; i++) {
      final id = flashes.entityAt(i);
      final f = flashes.denseAt(i);
      f.age = math.min(f.age + dt, f.life);
      final alpha = f.peak * (1 - f.age / f.life);
      final tint = tints.get(id);
      if (tint != null) {
        tint.colorArgb = (f.rgb & 0xFFFFFF) | ((alpha * 255).round() << 24);
      }
    }
  }
}
