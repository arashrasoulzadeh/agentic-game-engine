import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core_idle.dart';
import 'package:test/test.dart';

void main() {
  test('idleGameDefinitionJsonSchema names the document and its top keys', () {
    final s = idleGameDefinitionJsonSchema();
    expect(s[r'$schema'], contains('2020-12'));
    expect(s['title'], 'idle_game');
    final props = s['properties']! as Map;
    expect(
      props.keys,
      containsAll([
        'resources',
        'generators',
        'upgrades',
        'achievements',
        'prestige',
        'prestiges',
        'challenges',
        'autoBuyer',
        'golden',
        'offline',
      ]),
    );
  });

  test('the create-template idle_game.json passes validateIdleDefinition', () {
    final path = File(
      '../engine_cli/templates/idle_game/assets/idle_game.json',
    );
    final json =
        jsonDecode(path.readAsStringSync()) as Map<String, dynamic>;
    expect(validateIdleDefinition(json), isEmpty);
  });
}
