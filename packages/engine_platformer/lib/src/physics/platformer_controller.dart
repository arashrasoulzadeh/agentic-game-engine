/// Ground/wall state + movement-feel config for one entity, maintained
/// by `PlatformerSystem`/`TileCollisionSystem`/`JumpSystem`/`DashSystem`.
/// Set `jumpRequested`/`dashRequested = true` from your input-reading
/// code (e.g. `PlatformerInputSystem`) each tick the action is pressed
/// — the owning system consumes it (resets to `false`) whether or not
/// the action actually fires.
///
/// Every feel-mechanic field below defaults to "off, exactly like the
/// original strict grounded-only jump" — opting in is additive, never a
/// behavior change for a controller that doesn't set them.
class PlatformerController {
  bool grounded;
  double jumpSpeed;
  bool jumpRequested;

  // --- Movement-feel config (set once, e.g. from spawnPlayer) ---

  /// How long after leaving the ground a jump still counts as grounded
  /// ("coyote time"). `0` (default) disables it — a jump only fires the
  /// exact tick `grounded` is true, the original behavior.
  double coyoteTimeSeconds;

  /// How long a jump press is remembered if it happens slightly before
  /// landing ("jump buffering"). `0` (default) disables it — a jump
  /// only fires the exact tick it was requested.
  double jumpBufferSeconds;

  /// Extra jumps allowed while airborne, beyond the first. `0`
  /// (default, no double jump) means only a ground/coyote jump can
  /// fire; `1` is a standard double jump.
  int maxAirJumps;

  /// Horizontal push speed given by a jump made while touching a wall
  /// and airborne (see `touchingWallLeft`/`touchingWallRight`). `0`
  /// (default) disables wall jumping entirely.
  double wallJumpPushSpeed;

  /// Caps downward speed while airborne and touching a wall (a "wall
  /// slide"). `null` (default) disables it — falling speed is
  /// unaffected by wall contact.
  double? wallSlideMaxFallSpeed;

  /// Horizontal speed of a dash (see `dashRequested`/`DashSystem`). `0`
  /// (default) disables dashing entirely.
  double dashSpeed;

  /// How long a dash's speed burst lasts.
  double dashDurationSeconds;

  // --- Runtime state (maintained by the systems above) ---

  /// Seconds since `grounded` was last true this frame — `0` the tick
  /// it's actually grounded, incrementing every tick after. Read
  /// against `coyoteTimeSeconds` for "still counts as grounded."
  double timeSinceGrounded;

  /// Seconds since `jumpRequested` was last set — `0` the tick it's
  /// actually requested, incrementing every tick after. Read against
  /// `jumpBufferSeconds` for "still counts as requested."
  double timeSinceJumpPressed;

  /// How many of `maxAirJumps` have been used since last grounded.
  int airJumpsUsed;

  /// Whether a wall is touching this entity's left/right side this
  /// tick — reset every tick by whichever of `PlatformerSystem`/
  /// `TileCollisionSystem` last runs, same as `grounded`.
  bool touchingWallLeft;
  bool touchingWallRight;

  /// Set `true` from input-reading code each tick a dash is pressed —
  /// see `DashSystem`.
  bool dashRequested;

  /// Seconds of dash burst remaining; `> 0` while `DashSystem` is
  /// overriding horizontal velocity.
  double dashTimeRemaining;

  /// Whether a dash has been used since last grounded — reset
  /// alongside `airJumpsUsed`. A game wanting unlimited air dashes can
  /// reset this itself; the built-in `DashSystem` allows one per
  /// ground contact by default (mirrors `maxAirJumps`'s spirit, kept
  /// as a plain bool rather than a count since multi-dash is a rarer
  /// ask than double-jump).
  bool dashUsed;

  /// Last nonzero horizontal movement direction (`1` or `-1`) —
  /// updated by `PlatformerInputSystem`, read by `DashSystem` to know
  /// which way to dash when there's no horizontal input held down.
  double facingSign;

  PlatformerController({
    this.grounded = false,
    this.jumpSpeed = 300,
    this.jumpRequested = false,
    this.coyoteTimeSeconds = 0,
    this.jumpBufferSeconds = 0,
    this.maxAirJumps = 0,
    this.wallJumpPushSpeed = 0,
    this.wallSlideMaxFallSpeed,
    this.dashSpeed = 0,
    this.dashDurationSeconds = 0.15,
    this.timeSinceGrounded = 0,
    this.timeSinceJumpPressed = 1e9,
    this.airJumpsUsed = 0,
    this.touchingWallLeft = false,
    this.touchingWallRight = false,
    this.dashRequested = false,
    this.dashTimeRemaining = 0,
    this.dashUsed = false,
    this.facingSign = 1,
  });

  Map<String, dynamic> toJson() => {
        'grounded': grounded,
        'jumpSpeed': jumpSpeed,
        'jumpRequested': jumpRequested,
        'coyoteTimeSeconds': coyoteTimeSeconds,
        'jumpBufferSeconds': jumpBufferSeconds,
        'maxAirJumps': maxAirJumps,
        'wallJumpPushSpeed': wallJumpPushSpeed,
        if (wallSlideMaxFallSpeed != null) 'wallSlideMaxFallSpeed': wallSlideMaxFallSpeed,
        'dashSpeed': dashSpeed,
        'dashDurationSeconds': dashDurationSeconds,
        'timeSinceGrounded': timeSinceGrounded,
        'timeSinceJumpPressed': timeSinceJumpPressed,
        'airJumpsUsed': airJumpsUsed,
        'touchingWallLeft': touchingWallLeft,
        'touchingWallRight': touchingWallRight,
        'dashRequested': dashRequested,
        'dashTimeRemaining': dashTimeRemaining,
        'dashUsed': dashUsed,
        'facingSign': facingSign,
      };

  factory PlatformerController.fromJson(Map<String, dynamic> json) =>
      PlatformerController(
        grounded: json['grounded'] as bool? ?? false,
        jumpSpeed: (json['jumpSpeed'] as num?)?.toDouble() ?? 300,
        jumpRequested: json['jumpRequested'] as bool? ?? false,
        coyoteTimeSeconds: (json['coyoteTimeSeconds'] as num?)?.toDouble() ?? 0,
        jumpBufferSeconds: (json['jumpBufferSeconds'] as num?)?.toDouble() ?? 0,
        maxAirJumps: (json['maxAirJumps'] as num?)?.toInt() ?? 0,
        wallJumpPushSpeed: (json['wallJumpPushSpeed'] as num?)?.toDouble() ?? 0,
        wallSlideMaxFallSpeed: (json['wallSlideMaxFallSpeed'] as num?)?.toDouble(),
        dashSpeed: (json['dashSpeed'] as num?)?.toDouble() ?? 0,
        dashDurationSeconds: (json['dashDurationSeconds'] as num?)?.toDouble() ?? 0.15,
        timeSinceGrounded: (json['timeSinceGrounded'] as num?)?.toDouble() ?? 0,
        timeSinceJumpPressed: (json['timeSinceJumpPressed'] as num?)?.toDouble() ?? 1e9,
        airJumpsUsed: (json['airJumpsUsed'] as num?)?.toInt() ?? 0,
        touchingWallLeft: json['touchingWallLeft'] as bool? ?? false,
        touchingWallRight: json['touchingWallRight'] as bool? ?? false,
        dashRequested: json['dashRequested'] as bool? ?? false,
        dashTimeRemaining: (json['dashTimeRemaining'] as num?)?.toDouble() ?? 0,
        dashUsed: json['dashUsed'] as bool? ?? false,
        facingSign: (json['facingSign'] as num?)?.toDouble() ?? 1,
      );
}
