/// Ground state + jump input for one entity, maintained by
/// `PlatformerSystem`. Set `jumpRequested = true` from your input-reading
/// code (e.g. each tick if the jump action is pressed) — the system
/// consumes it (resets to false) whether or not the jump actually fires.
class PlatformerController {
  bool grounded;
  double jumpSpeed;
  bool jumpRequested;

  PlatformerController({
    this.grounded = false,
    this.jumpSpeed = 300,
    this.jumpRequested = false,
  });

  Map<String, dynamic> toJson() => {
        'grounded': grounded,
        'jumpSpeed': jumpSpeed,
        'jumpRequested': jumpRequested,
      };

  factory PlatformerController.fromJson(Map<String, dynamic> json) =>
      PlatformerController(
        grounded: json['grounded'] as bool? ?? false,
        jumpSpeed: (json['jumpSpeed'] as num?)?.toDouble() ?? 300,
        jumpRequested: json['jumpRequested'] as bool? ?? false,
      );
}
