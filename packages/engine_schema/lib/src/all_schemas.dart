import 'field_schema.dart';
import 'core_schemas.dart';
import 'flutter_schemas.dart';
import 'platformer_schemas.dart';

/// Every component schema the three engine packages register, keyed by the
/// component's registered name. The CLI and the studio validate against this
/// map, because they cannot register the components themselves: a pure-Dart
/// tool cannot import the Flutter-based packages that define them.
const allComponentSchemas = <String, ComponentSchema>{
  'position': positionSchema,
  'velocity': velocitySchema,
  'collider': colliderSchema,
  'aiState': aiStateSchema,
  'button': buttonSchema,
  'buttonHitBox': buttonHitBoxSchema,
  'roomExit': roomExitSchema,
  'tileMap': tileMapSchema,
  'particle': particleSchema,
  'particleEmitter': particleEmitterSchema,
  'tween': tweenSchema,
  'triggerZone': triggerZoneSchema,
  'pushable': pushableSchema,
  'dialogueGraph': dialogueGraphSchema,
  'gameState': gameStateSchema,
  'inventory': inventorySchema,
  'particleForces': particleForcesSchema,
  'hearing': hearingSchema,
  'soundEvent': soundEventSchema,
  'sprite': spriteSchema,
  'animationState': animationStateSchema,
  'inputState': inputStateSchema,
  'parallaxLayer': parallaxLayerSchema,
  'text': textSchema,
  'hudBar': hudBarSchema,
  'nineSliceSprite': nineSliceSpriteSchema,
  'animationTransition': animationTransitionSchema,
  'light2d': light2dSchema,
  'screenTint': screenTintSchema,
  'clipShape': clipShapeSchema,
  'playerOptions': playerOptionsSchema,
  'sceneTransition': sceneTransitionSchema,
  'gravity': gravitySchema,
  'platformBody': platformBodySchema,
  'platformerController': platformerControllerSchema,
  'movementAnimationSet': movementAnimationSetSchema,
  'jumpAnimationSet': jumpAnimationSetSchema,
  'jumpAnimationPhaseState': jumpAnimationPhaseStateSchema,
  'health': healthSchema,
  'checkpoint': checkpointSchema,
  'lastCheckpoint': lastCheckpointSchema,
  'projectile': projectileSchema,
  'healthHudLink': healthHudLinkSchema,
  'waterZone': waterZoneSchema,
  'weapon': weaponSchema,
  'enemyCombat': enemyCombatSchema,
  'parry': parrySchema,
};
