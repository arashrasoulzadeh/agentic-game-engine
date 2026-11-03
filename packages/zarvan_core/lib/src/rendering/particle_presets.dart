import 'dart:math' as math;

import 'particle_emitter.dart';

/// Ready-made [ParticleEmitter] settings for the effects nearly every game wants,
/// so the first hit spark does not need twenty fields filled in. Each is a
/// fresh emitter: tweak a field before attaching it, or pass the colour.
///
/// Angles follow screen coordinates (y grows downward), so "up" is `-pi / 2`.
/// A burst fires once when the system next steps (`burstCount` resets to 0);
/// a `rate` emitter keeps emitting until its entity is destroyed or the rate is
/// set to 0.
///
/// ```dart
/// world.setComponent(world.spawnAt(x, y), ParticlePresets.explosion());
/// ```
abstract final class ParticlePresets {
  /// A round blast: 40 particles in every direction, fading fast.
  static ParticleEmitter explosion({int colorArgb = 0xFFFFA030}) =>
      ParticleEmitter(
        burstCount: 40,
        speedMin: 80,
        speedMax: 220,
        lifetimeMin: 0.3,
        lifetimeMax: 0.8,
        startScale: 1.2,
        endScale: 0,
        colorArgb: colorArgb,
      );

  /// A short upward spray of 12 fast sparks, for a hit or a ricochet.
  static ParticleEmitter sparks({int colorArgb = 0xFFFFE070}) =>
      ParticleEmitter(
        burstCount: 12,
        speedMin: 100,
        speedMax: 260,
        angleMin: -math.pi * 0.85,
        angleMax: -math.pi * 0.15,
        lifetimeMin: 0.2,
        lifetimeMax: 0.5,
        startScale: 0.8,
        endScale: 0,
        colorArgb: colorArgb,
      );

  /// A steady rising plume that grows and fades; keeps emitting.
  static ParticleEmitter smoke({int colorArgb = 0xFF8A8A8A}) => ParticleEmitter(
    rate: 12,
    speedMin: 10,
    speedMax: 30,
    angleMin: -math.pi * 0.65,
    angleMax: -math.pi * 0.35,
    lifetimeMin: 1,
    lifetimeMax: 2,
    startScale: 0.5,
    endScale: 2,
    startAlpha: 0.6,
    endAlpha: 0,
    colorArgb: colorArgb,
  );

  /// A small flat puff of 8 particles, for a landing or a footstep.
  static ParticleEmitter dust({int colorArgb = 0xFFC8B89A}) => ParticleEmitter(
    burstCount: 8,
    speedMin: 15,
    speedMax: 50,
    angleMin: -math.pi,
    angleMax: 0,
    lifetimeMin: 0.2,
    lifetimeMax: 0.45,
    startScale: 0.7,
    endScale: 0,
    startAlpha: 0.7,
    colorArgb: colorArgb,
  );
}
