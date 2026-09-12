/// An axis-aligned rectangle used for platform/ground geometry —
/// distinct from `Collider` (a circle, used for entity-vs-entity
/// collision) because platformer ground detection needs flat, walkable
/// surfaces that a circle can't represent well.
class PlatformBody {
  double width;
  double height;

  /// A one-way platform can be landed on from above but never blocks
  /// movement from below or the sides (jump-through platforms).
  bool oneWay;

  PlatformBody(this.width, this.height, {this.oneWay = false});

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'oneWay': oneWay,
      };

  factory PlatformBody.fromJson(Map<String, dynamic> json) => PlatformBody(
        (json['width'] as num).toDouble(),
        (json['height'] as num).toDouble(),
        oneWay: json['oneWay'] as bool? ?? false,
      );
}
