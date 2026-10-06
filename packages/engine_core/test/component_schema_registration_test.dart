import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

/// One valid JSON sample per core-registered component, including every
/// optional key, shaped like the component's real `toJson` output. The drift
/// test round-trips each sample through the registry, so a schema that
/// disagrees with the component's actual keys fails here, not in the studio.
final _samples = <String, Map<String, dynamic>>{
  'position': {'x': 1.5, 'y': -2.0},
  'velocity': {'x': 0.0, 'y': 3.0},
  'collider': {
    'radius': 8.0,
    'blocksLight': false,
    'pushable': true,
    'collisionGroup': 1,
    'collisionMask': -1,
  },
  'aiState': {
    'behaviorId': 'patrol',
    'memory': {'target': 3},
  },
  'button': {'actionId': 'start'},
  'buttonHitBox': {'width': 40.0, 'height': 12.0},
  'roomExit': {'targetSceneId': 'cave', 'spawnPoint': 'entrance'},
  'tileMap': {
    'cols': 2,
    'rows': 1,
    'tileWidth': 16.0,
    'tileHeight': 16.0,
    'tiles': [0, 1],
    'solidTileIds': [1],
    'oneWayTileIds': [],
    'slopeUpRightTileIds': [],
    'slopeUpLeftTileIds': [],
    'ladderTileIds': [],
    'conveyorSpeedByTileId': {},
    'frictionByTileId': {},
    'atlasId': 'tiles',
    'regionByTileId': {'1': 'stone'},
    'zIndex': 0,
    'backgroundTiles': [0, 0],
    'foregroundTiles': [0, 0],
    'tileAnimations': {
      '1': [1, 2],
    },
    'tileAnimationFps': 6.0,
    'collisionGroups': {'1': 2},
  },
  'particle': {
    'age': 0.0,
    'lifetime': 1.0,
    'startScale': 1.0,
    'endScale': 0.0,
    'startAlpha': 1.0,
    'endAlpha': 0.0,
    'colorArgb': 4294967295,
    'zIndex': 0,
    'followEmitter': false,
    'emitterEntityId': 5,
  },
  'particleEmitter': {
    'rate': 10.0,
    'burstCount': 0,
    'speedMin': 20.0,
    'speedMax': 60.0,
    'angleMin': 0.0,
    'angleMax': 6.28,
    'lifetimeMin': 0.5,
    'lifetimeMax': 1.0,
    'startScale': 1.0,
    'endScale': 0.0,
    'startAlpha': 1.0,
    'endAlpha': 0.0,
    'colorArgb': 4294967295,
    'zIndex': 0,
    'emissionShape': 'point',
    'emissionRadius': 0.0,
    'emissionHalfWidth': 0.0,
    'emissionHalfHeight': 0.0,
    'edgeStartX': 0.0,
    'edgeStartY': 0.0,
    'edgeEndX': 0.0,
    'edgeEndY': 0.0,
    'followEmitter': false,
    'accumulator': 0.0,
  },
  'tween': {
    'from': 0.0,
    'to': 10.0,
    'duration': 1.0,
    'elapsed': 0.0,
    'loop': false,
    'pingPong': false,
    'easing': 'linear',
    'reversed': false,
  },
  'triggerZone': {
    'triggerId': 'door',
    'data': {'locked': true},
  },
  'pushable': {'pushSpeed': 2.5},
  'dialogueGraph': {
    'nodes': {
      'start': {
        'id': 'start',
        'textKey': 'greet',
        'onShowEvent': 'none',
        'choices': [
          {'textKey': 'bye', 'onSelectEvent': 'none'},
        ],
      },
    },
    'startNodeId': 'start',
    'metadata': {'author': 'studio'},
  },
  'gameState': {
    'data': {'flag': true},
    'migrationVersion': 1,
  },
  'inventory': {
    'items': {'coin': 3},
  },
  'particleForces': {
    'radius': 100.0,
    'strength': 500.0,
    'isWind': false,
    'windDirection': 0.0,
    'falloffExponent': 2.0,
  },
  'hearing': {'range': 120.0},
  'soundEvent': {
    'x': 1.0,
    'y': 2.0,
    'loudness': 3.0,
    'tag': 'footstep',
    'data': {'material': 'stone'},
  },
};

/// Samples go through a JSON round-trip so nested objects have the
/// `Map<String, dynamic>` runtime types real saved data has.
Map<String, dynamic> _json(String name) =>
    jsonDecode(jsonEncode(_samples[name])) as Map<String, dynamic>;

void main() {
  late World world;
  setUp(() {
    world = World(width: 800, height: 480);
    registerCoreComponents(world);
  });

  test('every sampled core component has a registered schema', () {
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
