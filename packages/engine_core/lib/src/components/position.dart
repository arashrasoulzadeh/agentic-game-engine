class Position {
  double x, y;
  Position(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory Position.fromJson(Map<String, dynamic> json) =>
      Position((json['x'] as num).toDouble(), (json['y'] as num).toDouble());
}
