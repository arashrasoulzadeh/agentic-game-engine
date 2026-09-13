/// Spawns `Particle` entities from this entity's `Position` each tick —
/// read by `ParticleSystem`. Supports both continuous emission ([rate]
/// particles/second, e.g. a torch or waterfall) and one-shot bursts
/// (set [burstCount] > 0, e.g. `emitter.burstCount = 20` for an
/// explosion — `ParticleSystem` consumes it back to 0 the tick it
/// fires, the same "request flag" pattern as
/// `PlatformerController.jumpRequested`). Both can be used on the same
/// emitter (e.g. a steady trickle plus an occasional burst).
///
/// New particles get a random angle in [angleMin, angleMax] (radians)
/// and speed in [speedMin, speedMax], then age from [startScale]/
/// [startAlpha] to [endScale]/[endAlpha] over a random lifetime in
/// [lifetimeMin, lifetimeMax] — see `Particle` for how that ramp is
/// computed.
class ParticleEmitter {
  double rate;
  int burstCount;
  double speedMin;
  double speedMax;
  double angleMin;
  double angleMax;
  double lifetimeMin;
  double lifetimeMax;
  double startScale;
  double endScale;
  double startAlpha;
  double endAlpha;
  int colorArgb;

  /// `Particle.zIndex` copied onto every particle this emitter spawns —
  /// see `Sprite.zIndex` (in `engine_flutter`) for the full draw-order
  /// rule this participates in.
  int zIndex;

  /// Fractional particles owed to the next tick(s) from [rate] — internal
  /// bookkeeping so a rate like 2.5/sec doesn't lose the ".5" every tick.
  double accumulator;

  ParticleEmitter({
    this.rate = 0,
    this.burstCount = 0,
    this.speedMin = 20,
    this.speedMax = 60,
    this.angleMin = 0,
    this.angleMax = 6.283185307179586, // 2*pi
    this.lifetimeMin = 0.5,
    this.lifetimeMax = 1.0,
    this.startScale = 1,
    this.endScale = 0,
    this.startAlpha = 1,
    this.endAlpha = 0,
    this.colorArgb = 0xFFFFFFFF,
    this.zIndex = 0,
    this.accumulator = 0,
  });

  Map<String, dynamic> toJson() => {
        'rate': rate,
        'burstCount': burstCount,
        'speedMin': speedMin,
        'speedMax': speedMax,
        'angleMin': angleMin,
        'angleMax': angleMax,
        'lifetimeMin': lifetimeMin,
        'lifetimeMax': lifetimeMax,
        'startScale': startScale,
        'endScale': endScale,
        'startAlpha': startAlpha,
        'endAlpha': endAlpha,
        'colorArgb': colorArgb,
        'zIndex': zIndex,
        'accumulator': accumulator,
      };

  factory ParticleEmitter.fromJson(Map<String, dynamic> json) => ParticleEmitter(
        rate: (json['rate'] as num?)?.toDouble() ?? 0,
        burstCount: (json['burstCount'] as num?)?.toInt() ?? 0,
        speedMin: (json['speedMin'] as num?)?.toDouble() ?? 20,
        speedMax: (json['speedMax'] as num?)?.toDouble() ?? 60,
        angleMin: (json['angleMin'] as num?)?.toDouble() ?? 0,
        angleMax: (json['angleMax'] as num?)?.toDouble() ?? 6.283185307179586,
        lifetimeMin: (json['lifetimeMin'] as num?)?.toDouble() ?? 0.5,
        lifetimeMax: (json['lifetimeMax'] as num?)?.toDouble() ?? 1.0,
        startScale: (json['startScale'] as num?)?.toDouble() ?? 1,
        endScale: (json['endScale'] as num?)?.toDouble() ?? 0,
        startAlpha: (json['startAlpha'] as num?)?.toDouble() ?? 1,
        endAlpha: (json['endAlpha'] as num?)?.toDouble() ?? 0,
        colorArgb: (json['colorArgb'] as num?)?.toInt() ?? 0xFFFFFFFF,
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
        accumulator: (json['accumulator'] as num?)?.toDouble() ?? 0,
      );
}
