/// Marks an entity as affected by `GravitySystem`. `scale` lets
/// individual entities feel heavier/lighter (e.g. reduced gravity while
/// a jump button is held) without a separate component type per case.
class Gravity {
  double scale;

  Gravity({this.scale = 1});

  Map<String, dynamic> toJson() => {'scale': scale};

  factory Gravity.fromJson(Map<String, dynamic> json) =>
      Gravity(scale: (json['scale'] as num?)?.toDouble() ?? 1);
}
