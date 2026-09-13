class Velocity {
  double x, y;
  Velocity(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory Velocity.fromJson(Map<String, dynamic> json) =>
      Velocity((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}
