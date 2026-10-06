import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// One valid JSON sample per Flutter-registered component, including every
/// optional key, shaped like the component's real `toJson` output. The drift
/// test round-trips each sample through the registry, so a schema that
/// disagrees with the component's actual keys fails here, not in the studio.
final _samples = <String, Map<String, dynamic>>{
  'sprite': {
    'atlasId': 'hero',
    'region': 'idle_0',
    'rotation': 0.0,
    'scaleX': 1.0,
    'scaleY': 1.0,
    'screenSpace': false,
    'offsetX': 0.0,
    'offsetY': 0.0,
    'zIndex': 0,
    'normalAtlasId': 'hero_normal',
  },
  'animationState': {
    'clip': {
      'name': 'idle',
      'frameRegions': ['idle_0'],
      'frameDurationSeconds': 0.1,
      'loop': true,
    },
    'frameIndex': 0,
    'elapsed': 0.0,
    'playing': true,
    'crossfadeSeconds': 0.0,
  },
  'inputState': {
    'pressed': ['jump'],
    'axes': {'horizontal': 0.5},
  },
  'parallaxLayer': {
    'atlasId': 'bg',
    'region': 'hills',
    'scrollFactorX': 0.5,
    'scrollFactorY': 0.0,
    'tileX': true,
    'tileY': false,
    'fitHeight': false,
    'zIndex': -10,
  },
  'text': {
    'text': 'Hello',
    'fontSize': 16.0,
    'colorArgb': 4294967295,
    'align': 'center',
    'screenSpace': false,
    'zIndex': 0,
    'maxWidth': 200.0,
    'textScale': 1.0,
  },
  'hudBar': {
    'value': 50.0,
    'maxValue': 100.0,
    'width': 100.0,
    'height': 12.0,
    'fillColorArgb': 4283300428,
    'backgroundColorArgb': 2147483648,
    'screenSpace': true,
    'zIndex': 0,
  },
  'nineSliceSprite': {
    'atlasId': 'ui',
    'region': 'panel',
    'width': 120.0,
    'height': 48.0,
    'insetLeft': 8.0,
    'insetTop': 8.0,
    'insetRight': 8.0,
    'insetBottom': 8.0,
    'zIndex': 0,
  },
  'animationTransition': {
    'atlasId': 'hero',
    'region': 'idle_0',
    'scaleX': 1.0,
    'scaleY': 1.0,
    'rotation': 0.0,
    'zIndex': 0,
    'remainingSeconds': 0.2,
    'totalSeconds': 0.2,
  },
  'light2d': {
    'radius': 100.0,
    'intensity': 1.0,
    'colorArgb': 16777215,
    'coneAngle': 90.0,
    'coneDirection': 0.0,
    'castsShadows': false,
    'blockOneWayPlatforms': false,
    'flickerSpeed': 0.0,
    'flickerAmount': 0.3,
    'flickerAffectsRadius': true,
    'baseIntensity': 1.0,
    'baseRadius': 100.0,
    'flickerElapsed': 0.0,
    'shadowRayCount': 48,
    'shadowSmoothingSeconds': 0.0,
    'shadowEdgeSoftness': 8.0,
    'minZIndex': 0,
    'maxZIndex': 5,
    'cacheShadowGeometry': false,
    'overbrightIntensity': 0.0,
    'openAirFalloffScale': 1.0,
    'useGpuShadows': false,
  },
  'screenTint': {'colorArgb': 4278190080},
  'clipShape': {
    'isCircle': true,
    'radius': 100.0,
    'width': 200.0,
    'height': 200.0,
    'mode': 'reveal',
    'softness': 0.0,
  },
  'playerOptions': {
    'masterVolume': 1.0,
    'musicVolume': 0.8,
    'sfxVolume': 0.9,
    'controlScheme': 'keyboard',
    'keyboardBindings': {'jump': 32},
    'gamepadBindings': {},
    'touchBindings': {'jump': 'tapRight'},
    'textScale': 1.0,
    'highContrast': false,
    'colorblindMode': 'none',
    'reduceMotion': false,
    'screenShakeIntensity': 1.0,
    'dialogueSpeed': 1.0,
    'locale': 'en',
    'showFpsOverlay': false,
    'custom': {},
  },
  'sceneTransition': {
    'config': {
      'type': 'fade',
      'duration': 0.5,
      'easing': 'easeInOutQuad',
      'fadeColorArgb': 4278190080,
    },
    'covering': true,
    'progress': 0.0,
    'isRunning': false,
    'isComplete': false,
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
  });

  test('every sampled Flutter component has a registered schema', () {
    for (final name in _samples.keys) {
      expect(world.components.schemaFor(name), isNotNull, reason: name);
    }
  });

  test('each schema matches the keys its component serializes back', () {
    final entity = world.spawn();
    for (final entry in _samples.entries) {
      world.components.applyToEntity(entity, {entry.key: _json(entry.key)});
      final serialized =
          world.components.serializeEntity(entity)[entry.key]
              as Map<String, dynamic>;
      final schema = world.components.schemaFor(entry.key)!;
      expect(
        serialized.keys.toSet(),
        schema.fieldNames.toSet(),
        reason: '${entry.key} drifted from its schema',
      );
    }
  });

  test('each sample passes its own schema validation', () {
    for (final entry in _samples.entries) {
      final schema = world.components.schemaFor(entry.key)!;
      expect(schema.validate(_json(entry.key)), isEmpty, reason: entry.key);
    }
  });
}
