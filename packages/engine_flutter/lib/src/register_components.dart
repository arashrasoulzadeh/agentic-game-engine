import 'package:engine_core/engine_core.dart';

import 'rendering/animation.dart';
import 'rendering/animation_transition.dart';
import 'rendering/clip_shape.dart';
import 'rendering/hud_bar.dart';
import 'rendering/light2d.dart';
import 'rendering/nine_slice_sprite.dart';
import 'rendering/parallax_layer.dart';
import 'rendering/screen_tint.dart';
import 'rendering/sprite.dart';
import 'rendering/text.dart';
import 'input/input.dart';
import 'logic/scene_transition.dart';

/// Registers engine_flutter's components on [world], mirroring
/// `registerCoreComponents`. `GameRunner` calls both automatically;
/// call this yourself only if you're wiring a `World` without `Game`.
void registerFlutterComponents(World world) {
  world.components.register<Sprite>(
    'sprite',
    (s) => s.toJson(),
    Sprite.fromJson,
    schema: const ComponentSchema('sprite', [
      FieldSchema('atlasId', FieldType.string),
      FieldSchema('region', FieldType.string),
      FieldSchema('rotation', FieldType.double, defaultValue: 0),
      FieldSchema('scaleX', FieldType.double, defaultValue: 1),
      FieldSchema('scaleY', FieldType.double, defaultValue: 1),
      FieldSchema('screenSpace', FieldType.bool, defaultValue: false),
      FieldSchema('offsetX', FieldType.double, defaultValue: 0),
      FieldSchema('offsetY', FieldType.double, defaultValue: 0),
      FieldSchema('zIndex', FieldType.int, defaultValue: 0),
      FieldSchema('normalAtlasId', FieldType.string, optional: true),
    ]),
  );
  world.components.register<AnimationState>(
    'animationState',
    (a) => a.toJson(),
    AnimationState.fromJson,
    schema: const ComponentSchema('animationState', [
      FieldSchema('clip', FieldType.object),
      FieldSchema('frameIndex', FieldType.int, min: 0, defaultValue: 0),
      FieldSchema('elapsed', FieldType.double, min: 0, defaultValue: 0),
      FieldSchema('playing', FieldType.bool, defaultValue: true),
      FieldSchema('crossfadeSeconds', FieldType.double, min: 0, defaultValue: 0),
    ]),
  );
  world.components.register<InputState>(
    'inputState',
    (i) => i.toJson(),
    InputState.fromJson,
    schema: const ComponentSchema('inputState', [
      FieldSchema('pressed', FieldType.list),
      FieldSchema('axes', FieldType.object),
    ]),
  );
  world.components.register<ParallaxLayer>(
    'parallaxLayer',
    (p) => p.toJson(),
    ParallaxLayer.fromJson,
    schema: const ComponentSchema('parallaxLayer', [
      FieldSchema('atlasId', FieldType.string),
      FieldSchema('region', FieldType.string),
      FieldSchema('scrollFactorX', FieldType.double, defaultValue: 0.5),
      FieldSchema('scrollFactorY', FieldType.double, defaultValue: 0),
      FieldSchema('tileX', FieldType.bool, defaultValue: true),
      FieldSchema('tileY', FieldType.bool, defaultValue: false),
      FieldSchema('fitHeight', FieldType.bool, defaultValue: false),
      FieldSchema('zIndex', FieldType.int, defaultValue: 0),
    ]),
  );
  world.components.register<Text>(
    'text',
    (t) => t.toJson(),
    Text.fromJson,
    schema: const ComponentSchema('text', [
      FieldSchema('text', FieldType.string),
      FieldSchema('fontSize', FieldType.double, min: 1, defaultValue: 16),
      FieldSchema('colorArgb', FieldType.int, defaultValue: 4294967295),
      FieldSchema('align', FieldType.enumeration, options: ['left', 'center', 'right'], defaultValue: 'center'),
      FieldSchema('screenSpace', FieldType.bool, defaultValue: false),
      FieldSchema('zIndex', FieldType.int, defaultValue: 0),
      FieldSchema('maxWidth', FieldType.double, min: 0, optional: true),
      FieldSchema('textScale', FieldType.double, min: 0, defaultValue: 1),
    ]),
  );
  world.components.register<HudBar>(
    'hudBar',
    (h) => h.toJson(),
    HudBar.fromJson,
    schema: const ComponentSchema('hudBar', [
      FieldSchema('value', FieldType.double, min: 0),
      FieldSchema('maxValue', FieldType.double, min: 0),
      FieldSchema('width', FieldType.double, min: 0, defaultValue: 100),
      FieldSchema('height', FieldType.double, min: 0, defaultValue: 12),
      FieldSchema('fillColorArgb', FieldType.int, defaultValue: 4283300428),
      FieldSchema('backgroundColorArgb', FieldType.int, defaultValue: 2147483648),
      FieldSchema('screenSpace', FieldType.bool, defaultValue: true),
      FieldSchema('zIndex', FieldType.int, defaultValue: 0),
    ]),
  );
  world.components.register<NineSliceSprite>(
    'nineSliceSprite',
    (n) => n.toJson(),
    NineSliceSprite.fromJson,
    schema: const ComponentSchema('nineSliceSprite', [
      FieldSchema('atlasId', FieldType.string),
      FieldSchema('region', FieldType.string),
      FieldSchema('width', FieldType.double, min: 0),
      FieldSchema('height', FieldType.double, min: 0),
      FieldSchema('insetLeft', FieldType.double, min: 0),
      FieldSchema('insetTop', FieldType.double, min: 0),
      FieldSchema('insetRight', FieldType.double, min: 0),
      FieldSchema('insetBottom', FieldType.double, min: 0),
      FieldSchema('zIndex', FieldType.int, defaultValue: 0),
    ]),
  );
  world.components.register<AnimationTransition>(
    'animationTransition',
    (a) => a.toJson(),
    AnimationTransition.fromJson,
    schema: const ComponentSchema('animationTransition', [
      FieldSchema('atlasId', FieldType.string),
      FieldSchema('region', FieldType.string),
      FieldSchema('scaleX', FieldType.double, defaultValue: 1),
      FieldSchema('scaleY', FieldType.double, defaultValue: 1),
      FieldSchema('rotation', FieldType.double, defaultValue: 0),
      FieldSchema('zIndex', FieldType.int, defaultValue: 0),
      FieldSchema('remainingSeconds', FieldType.double, min: 0),
      FieldSchema('totalSeconds', FieldType.double, min: 0),
    ]),
  );
  world.components.register<Light2D>(
    'light2d',
    (l) => l.toJson(),
    Light2D.fromJson,
    schema: const ComponentSchema('light2d', [
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
      FieldSchema('shadowSmoothingSeconds', FieldType.double, min: 0, defaultValue: 0),
      FieldSchema('shadowEdgeSoftness', FieldType.double, min: 0, defaultValue: 8),
      FieldSchema('minZIndex', FieldType.int, optional: true),
      FieldSchema('maxZIndex', FieldType.int, optional: true),
      FieldSchema('cacheShadowGeometry', FieldType.bool, defaultValue: false),
      FieldSchema('overbrightIntensity', FieldType.double, min: 0, defaultValue: 0),
      FieldSchema('openAirFalloffScale', FieldType.double, min: 0, defaultValue: 1),
      FieldSchema('useGpuShadows', FieldType.bool, defaultValue: false),
    ]),
  );
  world.components.register<ScreenTint>(
    'screenTint',
    (s) => s.toJson(),
    ScreenTint.fromJson,
    schema: const ComponentSchema('screenTint', [
      FieldSchema('colorArgb', FieldType.int),
    ]),
  );
  world.components.register<ClipShape>(
    'clipShape',
    (c) => c.toJson(),
    ClipShape.fromJson,
    schema: const ComponentSchema('clipShape', [
      FieldSchema('isCircle', FieldType.bool, defaultValue: true),
      FieldSchema('radius', FieldType.double, min: 0, defaultValue: 100),
      FieldSchema('width', FieldType.double, min: 0, defaultValue: 200),
      FieldSchema('height', FieldType.double, min: 0, defaultValue: 200),
      FieldSchema('mode', FieldType.enumeration, options: ['reveal', 'cutout'], defaultValue: 'reveal'),
      FieldSchema('softness', FieldType.double, min: 0, defaultValue: 0),
    ]),
  );
  world.components.register<PlayerOptions>(
    'playerOptions',
    (o) => o.toJson(),
    PlayerOptions.fromJson,
    schema: const ComponentSchema('playerOptions', [
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
    ]),
  );
  world.components.register<SceneTransition>(
    'sceneTransition',
    (s) => s.toJson(),
    SceneTransition.fromJson,
    schema: const ComponentSchema('sceneTransition', [
      FieldSchema('config', FieldType.object),
      FieldSchema('covering', FieldType.bool),
      FieldSchema('progress', FieldType.double, min: 0, max: 1),
      FieldSchema('isRunning', FieldType.bool),
      FieldSchema('isComplete', FieldType.bool),
    ]),
  );
}
