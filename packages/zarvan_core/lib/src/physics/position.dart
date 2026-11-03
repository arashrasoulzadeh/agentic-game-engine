/// A point in world space. Both coordinates default to 0, so `Position()` is
/// the origin, handy for entities that a system places later.
class Position {
  double x, y;
  Position([this.x = 0, this.y = 0]);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory Position.fromJson(Map<String, dynamic> json) =>
      Position((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}
