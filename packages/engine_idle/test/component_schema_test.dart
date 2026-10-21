import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:engine_schema/engine_schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// One valid JSON sample per idle component, shaped like its real toJson output. Round-tripping each
/// through the registry fails here, not in the studio, if a schema and a component disagree.
final _samples = <String, Map<String, dynamic>>{
  'generator': {
    'id': 'cursor',
    'name': 'Cursor',
    'owned': 3,
    'maxOwned': 100,
    'costResource': 'coins',
    'cost': {'type': 'geometric', 'base': '1.0e1', 'growth': 1.15},
    'output': {'coins': '1.0e-1'},
    'requires': ['science'],
  },
  'upgrade': {
    'id': 'x2',
    'name': 'Double cursors',
    'cost': {'coins': '5.0e1'},
    'target': 'cursor',
    'multiplier': '2.0e0',
    'purchased': false,
    'requires': ['science'],
  },
  'idleStats': {
    'runEarned': {'coins': '1.0e3'},
    'lifetimeEarned': {'coins': '1.0e9'},
    'prestigeCount': 2,
    'taps': 5,
    'secondsPlayed': 12.5,
  },
  'prestigeRule': {
    'currency': 'gems',
    'basedOn': 'coins',
    'divisor': '1.0e6',
    'exponent': 0.5,
    'bonusPerUnit': 0.1,
    'startingAmounts': {'coins': '1.0e1'},
    'keepUpgrades': false,
  },
  'achievement': {
    'id': 'rich',
    'name': 'Rich',
    'stat': 'lifetime:coins',
    'atLeast': '1.0e3',
    'reward': '2.0e0',
    'unlocked': false,
  },
  'boost': {'id': 'x2', 'multiplier': '2.0e0', 'remaining': 120.0},
  'idleModifiers': {
    'additive': {'flat': '1.0e1'},
    'multiplicative': {'prestige': '2.0e0'},
  },
};

void main() {
  late World world;
  setUp(() {
    world = World(width: 10, height: 10);
    registerCoreComponents(world);
    registerIdleComponents(world);
  });

  test(
    'every idle component is registered with a schema, and every sample validates against it',
    () {
      for (final name in _samples.keys) {
        expect(world.components.isRegistered(name), isTrue, reason: name);
        final schema = allComponentSchemas[name];
        expect(schema, isNotNull, reason: '$name has no schema');
        expect(schema!.validate(_samples[name]!), isEmpty, reason: name);
      }
    },
  );

  test('samples round-trip through the registry unchanged', () {
    for (final entry in _samples.entries) {
      final e = world.spawn();
      world.components.applyToEntity(e, {entry.key: entry.value});
      final back = world.components.serializeEntity(e)[entry.key];
      expect(
        jsonDecode(jsonEncode(back)),
        jsonDecode(jsonEncode(entry.value)),
        reason: entry.key,
      );
    }
  });

  test('a saved world restores the economy exactly', () {
    final e = world.spawn();
    world.components.applyToEntity(e, {'generator': _samples['generator']!});
    final snap = WorldSnapshot.capture(world);
    final w2 = World(width: 10, height: 10);
    registerCoreComponents(w2);
    registerIdleComponents(w2);
    snap.restoreInto(w2);
    expect(w2.storeOf<Generator>().get(e)!.owned, 3);
    expect(
      w2.storeOf<Generator>().get(e)!.cost.costOfNext(0),
      BigNumber.parse('10'),
    );
  });

  test('registering twice is harmless', () {
    registerIdleComponents(world);
    expect(world.components.isRegistered('generator'), isTrue);
  });
}
