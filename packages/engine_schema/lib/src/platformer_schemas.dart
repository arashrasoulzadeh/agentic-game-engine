import 'field_schema.dart';

// Schemas for components registered by engine_platformer. `inventory` is
// shared with engine_core (see core_schemas.dart).

const gravitySchema = ComponentSchema(
  'gravity',
  [
    FieldSchema('scale', FieldType.double, min: 0, defaultValue: 1),
    FieldSchema('fallMultiplier', FieldType.double, min: 0, defaultValue: 1),
  ],
);

const platformBodySchema = ComponentSchema(
  'platformBody',
  [
    FieldSchema('width', FieldType.double, required: true, min: 0),
    FieldSchema('height', FieldType.double, required: true, min: 0),
    FieldSchema('oneWay', FieldType.bool, defaultValue: false),
  ],
);

const platformerControllerSchema = ComponentSchema(
  'platformerController',
  [
    FieldSchema('grounded', FieldType.bool, defaultValue: false),
    FieldSchema('jumpSpeed', FieldType.double, min: 0, defaultValue: 300),
    FieldSchema('jumpRequested', FieldType.bool),
    FieldSchema('coyoteTimeSeconds', FieldType.double, min: 0),
    FieldSchema('jumpBufferSeconds', FieldType.double, min: 0),
    FieldSchema('maxAirJumps', FieldType.int, min: 0),
    FieldSchema('wallJumpPushSpeed', FieldType.double, min: 0),
    FieldSchema('wallSlideMaxFallSpeed', FieldType.double, min: 0, optional: true),
    FieldSchema('dashSpeed', FieldType.double, min: 0),
    FieldSchema('dashDurationSeconds', FieldType.double, min: 0),
    FieldSchema('jumpCutMultiplier', FieldType.double, min: 0),
    FieldSchema('timeSinceGrounded', FieldType.double, min: 0),
    FieldSchema('timeSinceJumpPressed', FieldType.double, min: 0),
    FieldSchema('airJumpsUsed', FieldType.int, min: 0),
    FieldSchema('touchingWallLeft', FieldType.bool),
    FieldSchema('touchingWallRight', FieldType.bool),
    FieldSchema('dashRequested', FieldType.bool),
    FieldSchema('dashTimeRemaining', FieldType.double, min: 0),
    FieldSchema('dashUsed', FieldType.bool),
    FieldSchema('jumpHeldLastTick', FieldType.bool),
    FieldSchema('hitstunSeconds', FieldType.double, min: 0),
    FieldSchema('facingSign', FieldType.double),
    FieldSchema('climbSpeed', FieldType.double, min: 0),
    FieldSchema('onLadder', FieldType.bool),
    FieldSchema('groundFriction', FieldType.double, min: 0),
    FieldSchema('ledgeGrabEnabled', FieldType.bool),
    FieldSchema('ledgeGrabbing', FieldType.bool),
    FieldSchema('ledgeMantleTargetX', FieldType.double),
    FieldSchema('ledgeMantleTargetY', FieldType.double),
    FieldSchema('inWater', FieldType.bool),
  ],
);

const movementAnimationSetSchema = ComponentSchema(
  'movementAnimationSet',
  [
    FieldSchema('idle', FieldType.object, required: true),
    FieldSchema('walk', FieldType.object, required: true),
    FieldSchema('jump', FieldType.object, optional: true),
    FieldSchema('moveThreshold', FieldType.double, min: 0),
  ],
);

const jumpAnimationSetSchema = ComponentSchema(
  'jumpAnimationSet',
  [
    FieldSchema('start', FieldType.object, required: true),
    FieldSchema('rising', FieldType.object, required: true),
    FieldSchema('peak', FieldType.object, required: true),
    FieldSchema('falling', FieldType.object, required: true),
    FieldSchema('landing', FieldType.object, required: true),
    FieldSchema('completed', FieldType.object, required: true),
    FieldSchema('peakVelocityThreshold', FieldType.double, min: 0),
    FieldSchema('startHoldSeconds', FieldType.double, min: 0),
    FieldSchema('landingHoldSeconds', FieldType.double, min: 0),
    FieldSchema('completedHoldSeconds', FieldType.double, min: 0),
    FieldSchema('moveInterruptThreshold', FieldType.double, min: 0),
  ],
);

const jumpAnimationPhaseStateSchema = ComponentSchema(
  'jumpAnimationPhaseState',
  [
    FieldSchema('elapsed', FieldType.double, min: 0),
  ],
);

const healthSchema = ComponentSchema(
  'health',
  [
    FieldSchema('current', FieldType.double, required: true, min: 0),
    FieldSchema('max', FieldType.double, required: true, min: 1),
    FieldSchema('invincibleSeconds', FieldType.double, min: 0),
    FieldSchema('isGuarding', FieldType.bool, defaultValue: false),
    FieldSchema('guardDamageReduction', FieldType.double, min: 0, max: 1, defaultValue: 1),
    FieldSchema('stability', FieldType.double, min: 0),
    FieldSchema('maxStability', FieldType.double, min: 0),
    FieldSchema('guardBreakStunSeconds', FieldType.double, min: 0),
    FieldSchema('guardBreakTimer', FieldType.double, min: 0),
    FieldSchema('stabilityRegenPerSecond', FieldType.double, min: 0),
  ],
);

const checkpointSchema = ComponentSchema(
  'checkpoint',
  [
    FieldSchema('id', FieldType.string, required: true),
    FieldSchema('activated', FieldType.bool, defaultValue: false),
  ],
);

const lastCheckpointSchema = ComponentSchema(
  'lastCheckpoint',
  [
    FieldSchema('x', FieldType.double, required: true),
    FieldSchema('y', FieldType.double, required: true),
  ],
);

const projectileSchema = ComponentSchema(
  'projectile',
  [
    FieldSchema('damage', FieldType.double, required: true, min: 0),
    FieldSchema('lifetimeSeconds', FieldType.double, min: 0),
    FieldSchema('elapsed', FieldType.double, min: 0),
    FieldSchema('owner', FieldType.int, optional: true),
  ],
);

const healthHudLinkSchema = ComponentSchema(
  'healthHudLink',
  [
    FieldSchema('source', FieldType.int, required: true),
  ],
);

const waterZoneSchema = ComponentSchema(
  'waterZone',
  [
    FieldSchema('width', FieldType.double, required: true, min: 0),
    FieldSchema('height', FieldType.double, required: true, min: 0),
    FieldSchema('maxFallSpeed', FieldType.double, min: 0),
    FieldSchema('swimUpSpeed', FieldType.double, min: 0),
  ],
);

const weaponSchema = ComponentSchema(
  'weapon',
  [
    FieldSchema('kind', FieldType.enumeration, options: ['melee', 'ranged'], defaultValue: 'melee'),
    FieldSchema('damage', FieldType.double, min: 0),
    FieldSchema('cooldownSeconds', FieldType.double, min: 0),
    FieldSchema('cooldownRemaining', FieldType.double, min: 0),
    FieldSchema('meleeRange', FieldType.double, min: 0),
    FieldSchema('meleeRadius', FieldType.double, min: 0),
    FieldSchema('meleeDurationSeconds', FieldType.double, min: 0),
    FieldSchema('projectileSpeed', FieldType.double, min: 0),
    FieldSchema('projectileRadius', FieldType.double, min: 0),
    FieldSchema('projectileLifetimeSeconds', FieldType.double, min: 0),
    FieldSchema('comboCount', FieldType.int, min: 0),
    FieldSchema('comboWindowSeconds', FieldType.double, min: 0),
    FieldSchema('comboTimer', FieldType.double, min: 0),
    FieldSchema('currentComboStep', FieldType.int, min: 0),
    FieldSchema('comboDamageMultipliers', FieldType.list, optional: true),
    FieldSchema('comboCooldowns', FieldType.list, optional: true),
    FieldSchema('comboMeleeRanges', FieldType.list, optional: true),
    FieldSchema('comboMeleeRadii', FieldType.list, optional: true),
    FieldSchema('comboMeleeDurations', FieldType.list, optional: true),
    FieldSchema('atlasId', FieldType.string, optional: true),
    FieldSchema('spriteRegion', FieldType.string, optional: true),
  ],
);

const enemyCombatSchema = ComponentSchema(
  'enemyCombat',
  [
    FieldSchema('state', FieldType.enumeration, options: ['idle', 'patrol', 'alert', 'approach', 'telegraph', 'attack', 'recovery', 'reposition', 'stagger', 'guard', 'retreat']),
    FieldSchema('stateTimer', FieldType.double, min: 0),
    FieldSchema('target', FieldType.int, optional: true),
    FieldSchema('detectionRange', FieldType.double, min: 0),
    FieldSchema('engageRange', FieldType.double, min: 0),
    FieldSchema('attackRange', FieldType.double, min: 0),
    FieldSchema('telegraphDuration', FieldType.double, min: 0),
    FieldSchema('attackDuration', FieldType.double, min: 0),
    FieldSchema('recoveryDuration', FieldType.double, min: 0),
    FieldSchema('repositionDuration', FieldType.double, min: 0),
    FieldSchema('staggerDuration', FieldType.double, min: 0),
    FieldSchema('guardDuration', FieldType.double, min: 0),
    FieldSchema('retreatHealthFraction', FieldType.double, min: 0, max: 1),
    FieldSchema('approachSpeed', FieldType.double, min: 0),
    FieldSchema('repositionSpeed', FieldType.double, min: 0),
    FieldSchema('retreatSpeed', FieldType.double, min: 0),
    FieldSchema('patrolSpeed', FieldType.double, min: 0),
    FieldSchema('patrolMinX', FieldType.double, optional: true),
    FieldSchema('patrolMaxX', FieldType.double, optional: true),
  ],
);

const parrySchema = ComponentSchema(
  'parry',
  [
    FieldSchema('parryTimer', FieldType.double, min: 0),
    FieldSchema('parryCooldownTimer', FieldType.double, min: 0),
    FieldSchema('parryWindowSeconds', FieldType.double, min: 0),
    FieldSchema('parryStunSeconds', FieldType.double, min: 0),
    FieldSchema('parryCooldownSeconds', FieldType.double, min: 0),
  ],
);
