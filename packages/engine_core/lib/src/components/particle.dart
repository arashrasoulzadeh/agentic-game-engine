/// One spawned particle: a fixed lifetime plus a scale/alpha ramp over
/// that lifetime, computed generically here so `engine_flutter`'s
/// renderer doesn't need particle-specific logic beyond reading
/// `scale`/`alpha`. `colorArgb` is a plain int (not a Flutter `Color`)
/// so this stays usable from pure-Dart code — `engine_core` has no
/// Flutter dependency. Spawned and aged by `ParticleSystem`; a game
/// doesn't normally construct these directly (see `ParticleEmitter`).
class Particle {
  double age;
  final double lifetime;
  final double startScale;
  final double endScale;
  final double startAlpha;
  final double endAlpha;
  final int colorArgb;

  Particle({
    this.age = 0,
    required this.lifetime,
    this.startScale = 1,
    this.endScale = 1,
    this.startAlpha = 1,
    this.endAlpha = 0,
    this.colorArgb = 0xFFFFFFFF,
  });

  double get progress => lifetime <= 0 ? 1 : (age / lifetime).clamp(0.0, 1.0);
  double get scale => startScale + (endScale - startScale) * progress;
  double get alpha => startAlpha + (endAlpha - startAlpha) * progress;
  bool get isExpired => age >= lifetime;

  Map<String, dynamic> toJson() => {
        'age': age,
        'lifetime': lifetime,
        'startScale': startScale,
        'endScale': endScale,
        'startAlpha': startAlpha,
        'endAlpha': endAlpha,
        'colorArgb': colorArgb,
      };

  factory Particle.fromJson(Map<String, dynamic> json) => Particle(
        age: (json['age'] as num?)?.toDouble() ?? 0,
        lifetime: (json['lifetime'] as num).toDouble(),
        startScale: (json['startScale'] as num?)?.toDouble() ?? 1,
        endScale: (json['endScale'] as num?)?.toDouble() ?? 1,
        startAlpha: (json['startAlpha'] as num?)?.toDouble() ?? 1,
        endAlpha: (json['endAlpha'] as num?)?.toDouble() ?? 0,
        colorArgb: (json['colorArgb'] as num?)?.toInt() ?? 0xFFFFFFFF,
      );
}
