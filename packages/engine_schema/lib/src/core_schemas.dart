import 'field_schema.dart';

// Schemas for components registered by engine_core. The field lists are data
// the studio and CLI read; each must match its component's toJson keys (see
// the drift tests in engine_core).

const positionSchema = ComponentSchema('position', [
  FieldSchema('x', FieldType.double, required: true, defaultValue: 0),
  FieldSchema('y', FieldType.double, required: true, defaultValue: 0),
]);

const velocitySchema = ComponentSchema('velocity', [
  FieldSchema('x', FieldType.double, required: true, defaultValue: 0),
  FieldSchema('y', FieldType.double, required: true, defaultValue: 0),
]);

const colliderSchema = ComponentSchema('collider', [
  FieldSchema('radius', FieldType.double, required: true, min: 0),
  FieldSchema('blocksLight', FieldType.bool, defaultValue: false),
  FieldSchema('pushable', FieldType.bool, defaultValue: true),
  FieldSchema('collisionGroup', FieldType.int, defaultValue: 1),
  FieldSchema('collisionMask', FieldType.int, defaultValue: -1),
]);

const aiStateSchema = ComponentSchema('aiState', [
  FieldSchema('behaviorId', FieldType.string, required: true),
  FieldSchema('memory', FieldType.object, optional: true),
]);

const buttonSchema = ComponentSchema('button', [
  FieldSchema('actionId', FieldType.string, required: true),
]);

const buttonHitBoxSchema = ComponentSchema('buttonHitBox', [
  FieldSchema('width', FieldType.double, required: true, min: 0),
  FieldSchema('height', FieldType.double, required: true, min: 0),
]);

const roomExitSchema = ComponentSchema('roomExit', [
  FieldSchema('targetSceneId', FieldType.string, required: true),
  FieldSchema('spawnPoint', FieldType.string, required: true),
]);

const tileMapSchema = ComponentSchema('tileMap', [
  FieldSchema('cols', FieldType.int, required: true, min: 1),
  FieldSchema('rows', FieldType.int, required: true, min: 1),
  FieldSchema('tileWidth', FieldType.double, required: true, min: 0),
  FieldSchema('tileHeight', FieldType.double, required: true, min: 0),
  FieldSchema('tiles', FieldType.list, required: true),
  FieldSchema('solidTileIds', FieldType.list),
  FieldSchema('oneWayTileIds', FieldType.list),
  FieldSchema('slopeUpRightTileIds', FieldType.list),
  FieldSchema('slopeUpLeftTileIds', FieldType.list),
  FieldSchema('ladderTileIds', FieldType.list),
  FieldSchema('conveyorSpeedByTileId', FieldType.object),
  FieldSchema('frictionByTileId', FieldType.object),
  FieldSchema('atlasId', FieldType.string, optional: true),
  FieldSchema('regionByTileId', FieldType.object),
  FieldSchema('zIndex', FieldType.int, defaultValue: 0),
  FieldSchema('backgroundTiles', FieldType.list, optional: true),
  FieldSchema('foregroundTiles', FieldType.list, optional: true),
  FieldSchema('tileAnimations', FieldType.object, optional: true),
  FieldSchema('tileAnimationFps', FieldType.double, min: 0, defaultValue: 6),
  FieldSchema('collisionGroups', FieldType.object, optional: true),
]);

const particleSchema = ComponentSchema('particle', [
  FieldSchema('age', FieldType.double, min: 0),
  FieldSchema('lifetime', FieldType.double, required: true, min: 0),
  FieldSchema('startScale', FieldType.double, min: 0),
  FieldSchema('endScale', FieldType.double, min: 0),
  FieldSchema('startAlpha', FieldType.double, min: 0, max: 1),
  FieldSchema('endAlpha', FieldType.double, min: 0, max: 1),
  FieldSchema('colorArgb', FieldType.int),
  FieldSchema('zIndex', FieldType.int),
  FieldSchema('followEmitter', FieldType.bool),
  FieldSchema('emitterEntityId', FieldType.int, optional: true),
]);

const particleEmitterSchema = ComponentSchema('particleEmitter', [
  FieldSchema('rate', FieldType.double, min: 0),
  FieldSchema('burstCount', FieldType.int, min: 0),
  FieldSchema('speedMin', FieldType.double, min: 0),
  FieldSchema('speedMax', FieldType.double, min: 0),
  FieldSchema('angleMin', FieldType.double),
  FieldSchema('angleMax', FieldType.double),
  FieldSchema('lifetimeMin', FieldType.double, min: 0),
  FieldSchema('lifetimeMax', FieldType.double, min: 0),
  FieldSchema('startScale', FieldType.double, min: 0),
  FieldSchema('endScale', FieldType.double, min: 0),
  FieldSchema('startAlpha', FieldType.double, min: 0, max: 1),
  FieldSchema('endAlpha', FieldType.double, min: 0, max: 1),
  FieldSchema('colorArgb', FieldType.int),
  FieldSchema('zIndex', FieldType.int),
  FieldSchema(
    'emissionShape',
    FieldType.enumeration,
    options: ['point', 'circle', 'rect', 'edge'],
    defaultValue: 'point',
  ),
  FieldSchema('emissionRadius', FieldType.double, min: 0),
  FieldSchema('emissionHalfWidth', FieldType.double, min: 0),
  FieldSchema('emissionHalfHeight', FieldType.double, min: 0),
  FieldSchema('edgeStartX', FieldType.double),
  FieldSchema('edgeStartY', FieldType.double),
  FieldSchema('edgeEndX', FieldType.double),
  FieldSchema('edgeEndY', FieldType.double),
  FieldSchema('followEmitter', FieldType.bool),
  FieldSchema('accumulator', FieldType.double, min: 0),
]);

const tweenSchema = ComponentSchema('tween', [
  FieldSchema('from', FieldType.double, required: true),
  FieldSchema('to', FieldType.double, required: true),
  FieldSchema('duration', FieldType.double, required: true, min: 0),
  FieldSchema('elapsed', FieldType.double, min: 0),
  FieldSchema('loop', FieldType.bool),
  FieldSchema('pingPong', FieldType.bool),
  FieldSchema(
    'easing',
    FieldType.enumeration,
    options: ['linear', 'easeInQuad', 'easeOutQuad', 'easeInOutQuad'],
    defaultValue: 'linear',
  ),
  FieldSchema('reversed', FieldType.bool),
]);

const triggerZoneSchema = ComponentSchema('triggerZone', [
  FieldSchema('triggerId', FieldType.string, required: true),
  FieldSchema('data', FieldType.object, optional: true),
]);

const pushableSchema = ComponentSchema('pushable', [
  FieldSchema('pushSpeed', FieldType.double, min: 0),
]);

const dialogueGraphSchema = ComponentSchema('dialogueGraph', [
  FieldSchema('nodes', FieldType.object, required: true),
  FieldSchema('startNodeId', FieldType.string, required: true),
  FieldSchema('metadata', FieldType.object, optional: true),
]);

const gameStateSchema = ComponentSchema('gameState', [
  FieldSchema('data', FieldType.object),
  FieldSchema('migrationVersion', FieldType.int, min: 1, defaultValue: 1),
]);

const inventorySchema = ComponentSchema('inventory', [
  FieldSchema('items', FieldType.object),
]);

const particleForcesSchema = ComponentSchema('particleForces', [
  FieldSchema('radius', FieldType.double, min: 0, defaultValue: 100),
  FieldSchema('strength', FieldType.double, defaultValue: 500),
  FieldSchema('isWind', FieldType.bool, defaultValue: false),
  FieldSchema('windDirection', FieldType.double, defaultValue: 0),
  FieldSchema('falloffExponent', FieldType.double, min: 0, defaultValue: 2),
]);

const hearingSchema = ComponentSchema('hearing', [
  FieldSchema('range', FieldType.double, required: true, min: 0),
]);

const soundEventSchema = ComponentSchema('soundEvent', [
  FieldSchema('x', FieldType.double, required: true),
  FieldSchema('y', FieldType.double, required: true),
  FieldSchema('loudness', FieldType.double, required: true, min: 0),
  FieldSchema('tag', FieldType.string, optional: true),
  FieldSchema('data', FieldType.object, optional: true),
]);

const teamSchema = ComponentSchema('team', [
  FieldSchema('id', FieldType.string, required: true),
]);

const actionPointsSchema = ComponentSchema('actionPoints', [
  FieldSchema('max', FieldType.int, min: 0, required: true),
  FieldSchema('current', FieldType.int, min: 0),
]);

const turnStateSchema = ComponentSchema('turnState', [
  FieldSchema('order', FieldType.list, required: true),
  FieldSchema('activeIndex', FieldType.int, min: 0),
  FieldSchema('round', FieldType.int, min: 1),
  FieldSchema('eliminated', FieldType.list),
  FieldSchema('winner', FieldType.string, optional: true),
]);

const gridPositionSchema = ComponentSchema('gridPosition', [
  FieldSchema('col', FieldType.int, required: true),
  FieldSchema('row', FieldType.int, required: true),
]);

const orderQueueSchema = ComponentSchema('orderQueue', [
  FieldSchema('orders', FieldType.list),
]);

const selectedSchema = ComponentSchema('selected', []);

const unitStatsSchema = ComponentSchema('unitStats', [
  FieldSchema('maxHp', FieldType.int, min: 1, required: true),
  FieldSchema('hp', FieldType.int, min: 0),
  FieldSchema('attack', FieldType.int, min: 0, defaultValue: 1),
  FieldSchema('defense', FieldType.int, min: 0, defaultValue: 0),
]);

const visionSchema = ComponentSchema('vision', [
  FieldSchema('range', FieldType.int, min: 0, required: true),
]);

const fogOfWarSchema = ComponentSchema('fogOfWar', [
  FieldSchema('cols', FieldType.int, min: 1, required: true),
  FieldSchema('rows', FieldType.int, min: 1, required: true),
  FieldSchema('visible', FieldType.object),
  FieldSchema('explored', FieldType.object),
]);

const attackProfileSchema = ComponentSchema('attackProfile', [
  FieldSchema('range', FieldType.int, min: 1, defaultValue: 1),
  FieldSchema('cost', FieldType.int, min: 0, defaultValue: 1),
]);

const statusEffectsSchema = ComponentSchema('statusEffects', [
  FieldSchema('effects', FieldType.list),
]);

const objectiveSchema = ComponentSchema('objective', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('col', FieldType.int, required: true),
  FieldSchema('row', FieldType.int, required: true),
  FieldSchema('owner', FieldType.string, optional: true),
]);

const objectiveRulesSchema = ComponentSchema('objectiveRules', [
  FieldSchema('holdTurnsToWin', FieldType.int, min: 1, required: true),
  FieldSchema('holds', FieldType.object),
]);

const realtimeStatsSchema = ComponentSchema('realtimeStats', [
  FieldSchema('speed', FieldType.double, min: 0, defaultValue: 2),
  FieldSchema('attackInterval', FieldType.double, min: 0, defaultValue: 1),
  FieldSchema('moveProgress', FieldType.double, min: 0),
  FieldSchema('cooldown', FieldType.double, min: 0),
]);

const vipSchema = ComponentSchema('vip', []);

const flagSchema = ComponentSchema('flag', [
  FieldSchema('id', FieldType.string, required: true),
  FieldSchema('homeTeam', FieldType.string, required: true),
  FieldSchema('homeCol', FieldType.int, required: true),
  FieldSchema('homeRow', FieldType.int, required: true),
  FieldSchema('col', FieldType.int),
  FieldSchema('row', FieldType.int),
  FieldSchema('carrier', FieldType.int, optional: true),
]);

const deliveryZoneSchema = ComponentSchema('deliveryZone', [
  FieldSchema('team', FieldType.string, required: true),
  FieldSchema('col', FieldType.int, required: true),
  FieldSchema('row', FieldType.int, required: true),
]);

const flagRulesSchema = ComponentSchema('flagRules', [
  FieldSchema('capturesToWin', FieldType.int, min: 1, required: true),
  FieldSchema('captures', FieldType.object),
]);

const treasurySchema = ComponentSchema('treasury', [
  FieldSchema('team', FieldType.string, required: true),
  FieldSchema('amounts', FieldType.object),
  FieldSchema('incomePerSecond', FieldType.object),
  FieldSchema('carry', FieldType.object),
]);

const producerSchema = ComponentSchema('producer', [
  FieldSchema('cost', FieldType.object),
  FieldSchema('seconds', FieldType.double, min: 0, required: true),
  FieldSchema('template', FieldType.object),
  FieldSchema('queued', FieldType.int, min: 0),
  FieldSchema('progress', FieldType.double, min: 0),
  FieldSchema('paid', FieldType.bool),
]);
