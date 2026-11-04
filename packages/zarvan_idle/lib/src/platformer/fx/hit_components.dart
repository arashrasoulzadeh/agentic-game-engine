/// A fighter knocked back along x; the sprite springs back as it ends.
class HitRecoil {
  HitRecoil({
    required this.direction,
    required this.amplitude,
    required this.life,
    this.age = 0,
  });

  /// -1 or +1: away from the attacker.
  final double direction;
  final double amplitude;
  final double life;
  double age;

  Map<String, dynamic> toJson() => {
    'direction': direction,
    'amplitude': amplitude,
    'life': life,
    'age': age,
  };

  factory HitRecoil.fromJson(Map<String, dynamic> json) => HitRecoil(
    direction: (json['direction'] as num).toDouble(),
    amplitude: (json['amplitude'] as num).toDouble(),
    life: (json['life'] as num).toDouble(),
    age: (json['age'] as num?)?.toDouble() ?? 0,
  );
}

/// A fading flash on a `ScreenTint` entity.
class ScreenFlash {
  ScreenFlash({
    required this.rgb,
    required this.peak,
    required this.life,
    this.age = 0,
  });

  final int rgb;
  final double peak;
  final double life;
  double age;

  Map<String, dynamic> toJson() => {
    'rgb': rgb,
    'peak': peak,
    'life': life,
    'age': age,
  };

  factory ScreenFlash.fromJson(Map<String, dynamic> json) => ScreenFlash(
    rgb: json['rgb'] as int,
    peak: (json['peak'] as num).toDouble(),
    life: (json['life'] as num).toDouble(),
    age: (json['age'] as num?)?.toDouble() ?? 0,
  );
}

/// A fighter tinted until [remaining] runs out: the glow of an attack wind-up.
class WindupTint {
  WindupTint({required this.remaining, required this.tintArgb});

  double remaining;

  /// The colour this wind-up applied, so only that tint is cleared when it ends
  /// (a hit flash that replaced it is left alone).
  final int tintArgb;

  Map<String, dynamic> toJson() => {
    'remaining': remaining,
    'tintArgb': tintArgb,
  };

  factory WindupTint.fromJson(Map<String, dynamic> json) => WindupTint(
    remaining: (json['remaining'] as num).toDouble(),
    tintArgb: json['tintArgb'] as int,
  );
}
