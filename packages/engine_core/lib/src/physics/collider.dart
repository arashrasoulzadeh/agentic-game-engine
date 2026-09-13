class Collider {
  double radius;
  Collider(this.radius);

  Map<String, dynamic> toJson() => {'radius': radius};
  factory Collider.fromJson(Map<String, dynamic> json) =>
      Collider((json['radius'] as num).toDouble());
}
