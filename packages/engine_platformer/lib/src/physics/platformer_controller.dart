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

  /// Multiplier applied once to `Velocity.y` the tick the jump button
  /// is released while still ascending (a "jump cut" / variable jump
  /// height — a quick tap gives a short hop, holding gives the full
  /// jump). `1.0` (default) disables it — releasing early has no
  /// effect, the original full-arc-regardless-of-hold behavior. A
  /// typical value is around `0.5`; `0` would zero all upward velocity
  /// instantly on release, which reads as a hard stop rather than a
  /// shortened arc.
  double jumpCutMultiplier;

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

  /// Whether the jump button was held (`jumpRequested`) as of last
  /// tick's `JumpSystem` pass — compared against this tick's
  /// `jumpRequested` to detect the release edge that triggers
  /// `jumpCutMultiplier`. Not meant to be set from game code.
  bool jumpHeldLastTick;

  /// Seconds remaining of "hitstun" — while `> 0`,
  /// `PlatformerInputSystem` ignores this entity's input entirely
  /// (movement, jump, dash), so a knockback impulse from `damageEntity`
  /// isn't immediately overridden by the player still holding a
  /// direction. Counted down by `HitstunSystem`. Set via
  /// `damageEntity`'s `hitstunSeconds` parameter, or directly for a
  /// custom hit-reaction of your own.
  double hitstunSeconds;

  /// Last nonzero horizontal movement direction (`1` or `-1`) —
  /// updated by `PlatformerInputSystem`, read by `DashSystem` to know
  /// which way to dash when there's no horizontal input held down.
  double facingSign;

  /// Vertical climb speed on a ladder tile (see `TileMap.ladderTileIds`).
  /// `0` (default) disables ladder climbing entirely — `LadderSystem`
  /// is a no-op for a controller that doesn't set this, same
  /// "off by default" convention as `wallJumpPushSpeed`.
  double climbSpeed;

  /// Whether this entity is overlapping a ladder tile this tick — set
  /// additively by `TileCollisionSystem`, reset (like `grounded`) by
  /// `PlatformerSystem` at the start of each entity's processing. Read
  /// by `LadderSystem` to know whether climbing input should apply.
  bool onLadder;

  /// Multiplier on how fast grounded horizontal velocity snaps to the
  /// input target, from the tile currently stood on (see
  /// `TileMap.frictionByTileId`). Reset to `1.0` (instant snap, the
  /// original behavior) each tick by `PlatformerSystem`, then set by
  /// `TileCollisionSystem` from whatever tile is landed on — so a
  /// controller that never touches a tagged tile behaves exactly as
  /// before.
  double groundFriction;

  /// `false` (default) disables ledge grab/mantle entirely —
  /// `LedgeGrabSystem` is a no-op for a controller that doesn't set
  /// this, same "off by default" convention as every other feel field
  /// here. When `true`, an airborne entity touching a wall right at
  /// the wall's top edge (open space directly above both the wall and
  /// the entity itself) grabs on instead of sliding/falling past it —
  /// see `LedgeGrabSystem`'s doc comment for exactly how the ledge is
  /// detected and how mantling up onto it works.
  bool ledgeGrabEnabled;

  /// Whether this entity is currently hanging from a grabbed ledge —
  /// maintained entirely by `LedgeGrabSystem`, not meant to be set from
  /// game code. While `true`, `Velocity` is frozen in place each tick
  /// until the entity mantles up (pressing jump/up) or drops
  /// (pressing down).
  bool ledgeGrabbing;

  /// Where `LedgeGrabSystem` moves this entity to when it mantles up
  /// off the currently grabbed ledge — computed once, at the moment
  /// the grab starts, from the tile geometry that triggered it, so
  /// mantling doesn't need to re-derive which wall/tile was grabbed.
  /// Meaningless while [ledgeGrabbing] is `false`.
  double ledgeMantleTargetX;
  double ledgeMantleTargetY;

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
    this.jumpCutMultiplier = 1.0,
    this.timeSinceGrounded = 0,
    this.timeSinceJumpPressed = 1e9,
    this.airJumpsUsed = 0,
    this.touchingWallLeft = false,
    this.touchingWallRight = false,
    this.dashRequested = false,
    this.dashTimeRemaining = 0,
    this.dashUsed = false,
    this.jumpHeldLastTick = false,
    this.hitstunSeconds = 0,
    this.facingSign = 1,
    this.climbSpeed = 0,
    this.onLadder = false,
    this.groundFriction = 1.0,
    this.ledgeGrabEnabled = false,
    this.ledgeGrabbing = false,
    this.ledgeMantleTargetX = 0,
    this.ledgeMantleTargetY = 0,
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
        'jumpCutMultiplier': jumpCutMultiplier,
        'timeSinceGrounded': timeSinceGrounded,
        'timeSinceJumpPressed': timeSinceJumpPressed,
        'airJumpsUsed': airJumpsUsed,
        'touchingWallLeft': touchingWallLeft,
        'touchingWallRight': touchingWallRight,
        'dashRequested': dashRequested,
        'dashTimeRemaining': dashTimeRemaining,
        'dashUsed': dashUsed,
        'jumpHeldLastTick': jumpHeldLastTick,
        'hitstunSeconds': hitstunSeconds,
        'facingSign': facingSign,
        'climbSpeed': climbSpeed,
        'onLadder': onLadder,
        'groundFriction': groundFriction,
        'ledgeGrabEnabled': ledgeGrabEnabled,
        'ledgeGrabbing': ledgeGrabbing,
        'ledgeMantleTargetX': ledgeMantleTargetX,
        'ledgeMantleTargetY': ledgeMantleTargetY,
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
        jumpCutMultiplier: (json['jumpCutMultiplier'] as num?)?.toDouble() ?? 1.0,
        timeSinceGrounded: (json['timeSinceGrounded'] as num?)?.toDouble() ?? 0,
        timeSinceJumpPressed: (json['timeSinceJumpPressed'] as num?)?.toDouble() ?? 1e9,
        airJumpsUsed: (json['airJumpsUsed'] as num?)?.toInt() ?? 0,
        touchingWallLeft: json['touchingWallLeft'] as bool? ?? false,
        touchingWallRight: json['touchingWallRight'] as bool? ?? false,
        dashRequested: json['dashRequested'] as bool? ?? false,
        dashTimeRemaining: (json['dashTimeRemaining'] as num?)?.toDouble() ?? 0,
        dashUsed: json['dashUsed'] as bool? ?? false,
        jumpHeldLastTick: json['jumpHeldLastTick'] as bool? ?? false,
        hitstunSeconds: (json['hitstunSeconds'] as num?)?.toDouble() ?? 0,
        facingSign: (json['facingSign'] as num?)?.toDouble() ?? 1,
        climbSpeed: (json['climbSpeed'] as num?)?.toDouble() ?? 0,
        onLadder: json['onLadder'] as bool? ?? false,
        groundFriction: (json['groundFriction'] as num?)?.toDouble() ?? 1.0,
        ledgeGrabEnabled: json['ledgeGrabEnabled'] as bool? ?? false,
        ledgeGrabbing: json['ledgeGrabbing'] as bool? ?? false,
        ledgeMantleTargetX: (json['ledgeMantleTargetX'] as num?)?.toDouble() ?? 0,
        ledgeMantleTargetY: (json['ledgeMantleTargetY'] as num?)?.toDouble() ?? 0,
      );
}
