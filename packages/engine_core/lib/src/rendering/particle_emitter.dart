/// Shape of particle emission area.
enum EmissionShape {
  /// Single point emission (current default behavior).
  point,

  /// Circular emission area (uniform in radius).
  circle,

  /// Rectangular emission area.
  rect,

  /// Edge emission (along a line segment).
  edge,
}

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
///
/// Supports multiple [EmissionShape]s (point, circle, rect, edge) and
/// can optionally make particles follow the emitter entity's position
/// (useful for trailing effects like magic sparkles on a moving character).
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

  /// Draw order for particles spawned by this emitter.
  int zIndex;

  /// Shape of the emission area. Default is [EmissionShape.point].
  EmissionShape emissionShape = EmissionShape.point;

  /// For [EmissionShape.circle]: radius of the emission circle.
  double emissionRadius = 0;

  /// For [EmissionShape.rect]: half-width and half-height of the rectangle.
  double emissionHalfWidth = 0;
  double emissionHalfHeight = 0;

  /// For [EmissionShape.edge]: start and end points of the line segment
  /// relative to the emitter's position.
  double edgeStartX = 0;
  double edgeStartY = 0;
  double edgeEndX = 0;
  double edgeEndY = 0;

  /// If true, spawned particles will follow this emitter entity's position.
  /// Useful for trailing effects that move with the emitter.
  bool followEmitter = false;

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
    this.emissionShape = EmissionShape.point,
    this.emissionRadius = 0,
    this.emissionHalfWidth = 0,
    this.emissionHalfHeight = 0,
    this.edgeStartX = 0,
    this.edgeStartY = 0,
    this.edgeEndX = 0,
    this.edgeEndY = 0,
    this.followEmitter = false,
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
        'emissionShape': emissionShape.name,
        'emissionRadius': emissionRadius,
        'emissionHalfWidth': emissionHalfWidth,
        'emissionHalfHeight': emissionHalfHeight,
        'edgeStartX': edgeStartX,
        'edgeStartY': edgeStartY,
        'edgeEndX': edgeEndX,
        'edgeEndY': edgeEndY,
        'followEmitter': followEmitter,
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
        emissionShape: EmissionShape.values.firstWhere(
          (e) => e.name == (json['emissionShape'] as String? ?? 'point'),
          orElse: () => EmissionShape.point,
        ),
        emissionRadius: (json['emissionRadius'] as num?)?.toDouble() ?? 0,
        emissionHalfWidth: (json['emissionHalfWidth'] as num?)?.toDouble() ?? 0,
        emissionHalfHeight: (json['emissionHalfHeight'] as num?)?.toDouble() ?? 0,
        edgeStartX: (json['edgeStartX'] as num?)?.toDouble() ?? 0,
        edgeStartY: (json['edgeStartY'] as num?)?.toDouble() ?? 0,
        edgeEndX: (json['edgeEndX'] as num?)?.toDouble() ?? 0,
        edgeEndY: (json['edgeEndY'] as num?)?.toDouble() ?? 0,
        followEmitter: (json['followEmitter'] as bool?) ?? false,
        accumulator: (json['accumulator'] as num?)?.toDouble() ?? 0,
      );
}
