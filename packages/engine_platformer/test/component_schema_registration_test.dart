import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Clip JSON shared by the animation-set samples, shaped like
/// `AnimationClip.toJson`.
const _clip = {
  'name': 'idle',
  'frameRegions': ['idle_0'],
  'frameDurationSeconds': 0.1,
  'loop': true,
};

/// One valid JSON sample per platformer-registered component, including every
/// optional key, shaped like the component's real `toJson` output. The drift
/// test round-trips each sample through the registry, so a schema that
/// disagrees with the component's actual keys fails here, not in the studio.
final _samples = <String, Map<String, dynamic>>{
  'gravity': {'scale': 1.0, 'fallMultiplier': 1.0},
  'platformBody': {'width': 16.0, 'height': 32.0, 'oneWay': false},
  'platformerController': {
    'grounded': false,
    'jumpSpeed': 300.0,
    'jumpRequested': false,
    'coyoteTimeSeconds': 0.1,
    'jumpBufferSeconds': 0.1,
    'maxAirJumps': 1,
    'wallJumpPushSpeed': 200.0,
    'wallSlideMaxFallSpeed': 60.0,
    'dashSpeed': 400.0,
    'dashDurationSeconds': 0.2,
    'jumpCutMultiplier': 0.5,
    'timeSinceGrounded': 0.0,
    'timeSinceJumpPressed': 0.0,
    'airJumpsUsed': 0,
    'touchingWallLeft': false,
    'touchingWallRight': false,
    'dashRequested': false,
    'dashTimeRemaining': 0.0,
    'dashUsed': false,
    'jumpHeldLastTick': false,
    'hitstunSeconds': 0.0,
    'facingSign': 1.0,
    'climbSpeed': 80.0,
    'onLadder': false,
    'groundFriction': 1.0,
    'ledgeGrabEnabled': false,
    'ledgeGrabbing': false,
    'ledgeMantleTargetX': 0.0,
    'ledgeMantleTargetY': 0.0,
    'inWater': false,
  },
  'movementAnimationSet': {
    'idle': _clip,
    'walk': _clip,
    'jump': _clip,
    'moveThreshold': 5.0,
  },
  'jumpAnimationSet': {
    'start': _clip,
    'rising': _clip,
    'peak': _clip,
    'falling': _clip,
    'landing': _clip,
    'completed': _clip,
    'peakVelocityThreshold': 50.0,
    'startHoldSeconds': 0.05,
    'landingHoldSeconds': 0.05,
    'completedHoldSeconds': 0.05,
    'moveInterruptThreshold': 10.0,
  },
  'jumpAnimationPhaseState': {'elapsed': 0.0},
  'health': {
    'current': 100.0,
    'max': 100.0,
    'invincibleSeconds': 0.0,
    'isGuarding': false,
    'guardDamageReduction': 0.5,
    'stability': 0.0,
    'maxStability': 100.0,
    'guardBreakStunSeconds': 1.0,
    'guardBreakTimer': 0.0,
    'stabilityRegenPerSecond': 10.0,
  },
  'checkpoint': {'id': 'cp1', 'activated': false},
  'lastCheckpoint': {'x': 10.0, 'y': 20.0},
  'inventory': {
    'items': {'coin': 3},
  },
  'projectile': {
    'damage': 5.0,
    'lifetimeSeconds': 3.0,
    'elapsed': 0.0,
    'owner': 2,
  },
  'healthHudLink': {'source': 7},
  'waterZone': {
    'width': 200.0,
    'height': 80.0,
    'maxFallSpeed': 80.0,
    'swimUpSpeed': 140.0,
  },
  'weapon': {
    'kind': 'melee',
    'damage': 10.0,
    'cooldownSeconds': 0.5,
    'cooldownRemaining': 0.0,
    'meleeRange': 24.0,
    'meleeRadius': 12.0,
    'meleeDurationSeconds': 0.2,
    'projectileSpeed': 300.0,
    'projectileRadius': 4.0,
    'projectileLifetimeSeconds': 2.0,
    'comboCount': 0,
    'comboWindowSeconds': 0.4,
    'comboTimer': 0.0,
    'currentComboStep': 0,
    'comboDamageMultipliers': [1.0, 1.5],
    'comboCooldowns': [0.5, 0.6],
    'comboMeleeRanges': [24.0, 28.0],
    'comboMeleeRadii': [12.0, 14.0],
    'comboMeleeDurations': [0.2, 0.25],
    'atlasId': 'weapons',
    'spriteRegion': 'sword',
  },
  'enemyCombat': {
    'state': 'idle',
    'stateTimer': 0.0,
    'target': 4,
    'detectionRange': 200.0,
    'engageRange': 120.0,
    'attackRange': 40.0,
    'telegraphDuration': 0.3,
    'attackDuration': 0.2,
    'recoveryDuration': 0.4,
    'repositionDuration': 0.5,
    'staggerDuration': 0.3,
    'guardDuration': 0.6,
    'retreatHealthFraction': 0.2,
    'approachSpeed': 90.0,
    'repositionSpeed': 60.0,
    'retreatSpeed': 120.0,
    'patrolSpeed': 40.0,
    'patrolMinX': 0.0,
    'patrolMaxX': 300.0,
  },
  'parry': {
    'parryTimer': 0.0,
    'parryCooldownTimer': 0.0,
    'parryWindowSeconds': 0.15,
    'parryStunSeconds': 0.5,
    'parryCooldownSeconds': 0.5,
  },
};

/// Samples go through a JSON round-trip so nested objects have the
/// `Map<String, dynamic>` runtime types real saved data has. A literal `{}`
/// is `Map<dynamic, dynamic>`, which a `fromJson` cast rejects.
Map<String, dynamic> _json(String name) =>
    jsonDecode(jsonEncode(_samples[name])) as Map<String, dynamic>;

void main() {
  late World world;
  setUp(() {
    world = World(width: 800, height: 480);
    registerCoreComponents(world);
    registerFlutterComponents(world);
    registerPlatformerComponents(world);
  });

  test('every sampled platformer component has a registered schema', () {
    for (final name in _samples.keys) {
      expect(world.components.schemaFor(name), isNotNull, reason: name);
    }
  });

  test('each schema matches the keys its component serializes back', () {
    final entity = world.spawn();
    for (final name in _samples.keys) {
      world.components.applyToEntity(entity, {name: _json(name)});
      final serialized =
          world.components.serializeEntity(entity)[name]
              as Map<String, dynamic>;
      final schema = world.components.schemaFor(name)!;
      expect(
        serialized.keys.toSet(),
        schema.fieldNames.toSet(),
        reason: '$name drifted from its schema',
      );
    }
  });

  test('each sample passes its own schema validation', () {
    for (final name in _samples.keys) {
      final schema = world.components.schemaFor(name)!;
      expect(schema.validate(_json(name)), isEmpty, reason: name);
    }
  });
}
