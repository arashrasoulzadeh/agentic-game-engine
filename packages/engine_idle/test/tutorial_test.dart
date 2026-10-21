import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle_logic.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the edits the idle tutorial tells the reader to make, against the template the CLI generates, so
/// the tutorial cannot drift from the file it describes.
void main() {
  test(
    'the tutorial\'s factory edit validates and plays on the generated template',
    () {
      final json =
          jsonDecode(
                File(
                  '../engine_cli/templates/idle_game/assets/idle_game.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      (json['generators'] as List).add(
        jsonDecode('''
{ "id": "factory", "name": "Factory",
  "cost": { "type": "geometric", "base": "130000", "growth": 1.15 },
  "output": { "coins": "260" },
  "milestones": [ { "owned": 25, "multiplier": "2" }, { "owned": 50, "multiplier": "2" } ] }
'''),
      );
      expect(validateIdleDefinition(json), isEmpty);

      final table = jsonDecode(
        '{ "type": "table", "prices": ["10", "25", "60"], "tailGrowth": 1.2 }',
      );
      ((json['generators'] as List).first as Map)['cost'] = table;
      expect(validateIdleDefinition(json), isEmpty);

      final world = World(width: 10, height: 10);
      registerCoreComponents(world);
      final game = loadIdleDefinition(world, json);
      final report = simulateIdle(
        world,
        game.wallet,
        limit: const Duration(days: 1),
      );
      expect(report.stalled, isFalse);
      expect(report.purchases, greaterThan(10));
    },
  );
}
