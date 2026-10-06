import 'field_schema.dart';

// Schemas for components registered by engine_flutter. See core_schemas.dart
// for the contract each must meet.

const spriteSchema = ComponentSchema('sprite', [
  FieldSchema('atlasId', FieldType.string, required: true),
  FieldSchema('region', FieldType.string, required: true),
  FieldSchema('rotation', FieldType.double, defaultValue: 0),
  FieldSchema('scaleX', FieldType.double, defaultValue: 1),
  FieldSchema('scaleY', FieldType.double, defaultValue: 1),
  FieldSchema('screenSpace', FieldType.bool, defaultValue: false),
  FieldSchema('offsetX', FieldType.double, defaultValue: 0),
  FieldSchema('offsetY', FieldType.double, defaultValue: 0),
  FieldSchema('zIndex', FieldType.int, defaultValue: 0),
  FieldSchema('normalAtlasId', FieldType.string, optional: true),
]);

const animationStateSchema = ComponentSchema('animationState', [
  FieldSchema('clip', FieldType.object, required: true),
  FieldSchema('frameIndex', FieldType.int, min: 0, defaultValue: 0),
  FieldSchema('elapsed', FieldType.double, min: 0, defaultValue: 0),
  FieldSchema('playing', FieldType.bool, defaultValue: true),
  FieldSchema('crossfadeSeconds', FieldType.double, min: 0, defaultValue: 0),
]);

const inputStateSchema = ComponentSchema('inputState', [
  FieldSchema('pressed', FieldType.list),
  FieldSchema('axes', FieldType.object),
]);

const parallaxLayerSchema = ComponentSchema('parallaxLayer', [
  FieldSchema('atlasId', FieldType.string, required: true),
  FieldSchema('region', FieldType.string, required: true),
  FieldSchema('scrollFactorX', FieldType.double, defaultValue: 0.5),
  FieldSchema('scrollFactorY', FieldType.double, defaultValue: 0),
  FieldSchema('tileX', FieldType.bool, defaultValue: true),
  FieldSchema('tileY', FieldType.bool, defaultValue: false),
  FieldSchema('fitHeight', FieldType.bool, defaultValue: false),
  FieldSchema('zIndex', FieldType.int, defaultValue: 0),
]);

const textSchema = ComponentSchema('text', [
  FieldSchema('text', FieldType.string, required: true),
  FieldSchema('fontSize', FieldType.double, min: 1, defaultValue: 16),
  FieldSchema('colorArgb', FieldType.int, defaultValue: 4294967295),
  FieldSchema(
    'align',
    FieldType.enumeration,
    options: ['left', 'center', 'right'],
    defaultValue: 'center',
  ),
  FieldSchema('screenSpace', FieldType.bool, defaultValue: false),
  FieldSchema('zIndex', FieldType.int, defaultValue: 0),
  FieldSchema('maxWidth', FieldType.double, min: 0, optional: true),
  FieldSchema('textScale', FieldType.double, min: 0, defaultValue: 1),
]);

const hudBarSchema = ComponentSchema('hudBar', [
  FieldSchema('value', FieldType.double, required: true, min: 0),
  FieldSchema('maxValue', FieldType.double, required: true, min: 0),
  FieldSchema('width', FieldType.double, min: 0, defaultValue: 100),
  FieldSchema('height', FieldType.double, min: 0, defaultValue: 12),
  FieldSchema('fillColorArgb', FieldType.int, defaultValue: 4283300428),
  FieldSchema('backgroundColorArgb', FieldType.int, defaultValue: 2147483648),
  FieldSchema('screenSpace', FieldType.bool, defaultValue: true),
  FieldSchema('zIndex', FieldType.int, defaultValue: 0),
]);

const nineSliceSpriteSchema = ComponentSchema('nineSliceSprite', [
  FieldSchema('atlasId', FieldType.string, required: true),
  FieldSchema('region', FieldType.string, required: true),
  FieldSchema('width', FieldType.double, required: true, min: 0),
  FieldSchema('height', FieldType.double, required: true, min: 0),
  FieldSchema('insetLeft', FieldType.double, required: true, min: 0),
  FieldSchema('insetTop', FieldType.double, required: true, min: 0),
  FieldSchema('insetRight', FieldType.double, required: true, min: 0),
  FieldSchema('insetBottom', FieldType.double, required: true, min: 0),
  FieldSchema('zIndex', FieldType.int, defaultValue: 0),
]);

const animationTransitionSchema = ComponentSchema('animationTransition', [
  FieldSchema('atlasId', FieldType.string, required: true),
  FieldSchema('region', FieldType.string, required: true),
  FieldSchema('scaleX', FieldType.double, defaultValue: 1),
  FieldSchema('scaleY', FieldType.double, defaultValue: 1),
  FieldSchema('rotation', FieldType.double, defaultValue: 0),
  FieldSchema('zIndex', FieldType.int, defaultValue: 0),
  FieldSchema('remainingSeconds', FieldType.double, required: true, min: 0),
  FieldSchema('totalSeconds', FieldType.double, required: true, min: 0),
]);

const light2dSchema = ComponentSchema('light2d', [
  FieldSchema('radius', FieldType.double, min: 0, defaultValue: 100),
  FieldSchema('intensity', FieldType.double, min: 0, defaultValue: 1),
  FieldSchema('colorArgb', FieldType.int, defaultValue: 16777215),
  FieldSchema('coneAngle', FieldType.double, min: 0, optional: true),
  FieldSchema('coneDirection', FieldType.double, defaultValue: 0),
  FieldSchema('castsShadows', FieldType.bool, defaultValue: false),
  FieldSchema('blockOneWayPlatforms', FieldType.bool, defaultValue: false),
  FieldSchema('flickerSpeed', FieldType.double, min: 0, defaultValue: 0),
  FieldSchema('flickerAmount', FieldType.double, min: 0, defaultValue: 0.3),
  FieldSchema('flickerAffectsRadius', FieldType.bool, defaultValue: true),
  FieldSchema('baseIntensity', FieldType.double, min: 0, optional: true),
  FieldSchema('baseRadius', FieldType.double, min: 0, optional: true),
  FieldSchema('flickerElapsed', FieldType.double, min: 0, defaultValue: 0),
  FieldSchema('shadowRayCount', FieldType.int, min: 1, defaultValue: 48),
  FieldSchema(
    'shadowSmoothingSeconds',
    FieldType.double,
    min: 0,
    defaultValue: 0,
  ),
  FieldSchema('shadowEdgeSoftness', FieldType.double, min: 0, defaultValue: 8),
  FieldSchema('minZIndex', FieldType.int, optional: true),
  FieldSchema('maxZIndex', FieldType.int, optional: true),
  FieldSchema('cacheShadowGeometry', FieldType.bool, defaultValue: false),
  FieldSchema('overbrightIntensity', FieldType.double, min: 0, defaultValue: 0),
  FieldSchema('openAirFalloffScale', FieldType.double, min: 0, defaultValue: 1),
  FieldSchema('useGpuShadows', FieldType.bool, defaultValue: false),
]);

const screenTintSchema = ComponentSchema('screenTint', [
  FieldSchema('colorArgb', FieldType.int, required: true),
]);

const clipShapeSchema = ComponentSchema('clipShape', [
  FieldSchema('isCircle', FieldType.bool, defaultValue: true),
  FieldSchema('radius', FieldType.double, min: 0, defaultValue: 100),
  FieldSchema('width', FieldType.double, min: 0, defaultValue: 200),
  FieldSchema('height', FieldType.double, min: 0, defaultValue: 200),
  FieldSchema(
    'mode',
    FieldType.enumeration,
    options: ['reveal', 'cutout'],
    defaultValue: 'reveal',
  ),
  FieldSchema('softness', FieldType.double, min: 0, defaultValue: 0),
]);

const playerOptionsSchema = ComponentSchema('playerOptions', [
  FieldSchema('masterVolume', FieldType.double, min: 0, max: 1),
  FieldSchema('musicVolume', FieldType.double, min: 0, max: 1),
  FieldSchema('sfxVolume', FieldType.double, min: 0, max: 1),
  FieldSchema('controlScheme', FieldType.string),
  FieldSchema('keyboardBindings', FieldType.object),
  FieldSchema('gamepadBindings', FieldType.object),
  FieldSchema('touchBindings', FieldType.object),
  FieldSchema('textScale', FieldType.double, min: 0),
  FieldSchema('highContrast', FieldType.bool),
  FieldSchema('colorblindMode', FieldType.string),
  FieldSchema('reduceMotion', FieldType.bool),
  FieldSchema('screenShakeIntensity', FieldType.double, min: 0),
  FieldSchema('dialogueSpeed', FieldType.double, min: 0),
  FieldSchema('locale', FieldType.string),
  FieldSchema('showFpsOverlay', FieldType.bool),
  FieldSchema('custom', FieldType.object),
]);

const sceneTransitionSchema = ComponentSchema('sceneTransition', [
  FieldSchema('config', FieldType.object, required: true),
  FieldSchema('covering', FieldType.bool),
  FieldSchema('progress', FieldType.double, min: 0, max: 1),
  FieldSchema('isRunning', FieldType.bool),
  FieldSchema('isComplete', FieldType.bool),
]);
