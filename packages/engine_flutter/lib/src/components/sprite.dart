/// Data-only sprite reference: which atlas, which named region, and a
/// simple transform. Resolved against an `AtlasRegistry` at render time,
/// which keeps this component plain-JSON serializable for agent authoring.
class Sprite {
  String atlasId;
  String region;
  double rotation;
  double scaleX;
  double scaleY;

  Sprite(
    this.atlasId,
    this.region, {
    this.rotation = 0,
    this.scaleX = 1,
    this.scaleY = 1,
  });

  Map<String, dynamic> toJson() => {
        'atlasId': atlasId,
        'region': region,
        'rotation': rotation,
        'scaleX': scaleX,
        'scaleY': scaleY,
      };

  factory Sprite.fromJson(Map<String, dynamic> json) => Sprite(
        json['atlasId'] as String,
        json['region'] as String,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        scaleX: (json['scaleX'] as num?)?.toDouble() ?? 1,
        scaleY: (json['scaleY'] as num?)?.toDouble() ?? 1,
      );
}
