import 'dart:convert';

import '../../content/level.dart';
import '../../physics/tile_map.dart';
import '../../validation/reachability.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';
import 'level_ops.dart';

/// `level.lint`: the loadability check plus, on request, the studio's walk/fall/jump reachability heuristic.
///
/// The PNG render of `game_agent lint --render` is not part of this operation: it needs an image codec, which
/// the pure-Dart core does not carry. The CLI keeps that flag.
List<Operation> levelLintOperations() => [
  Operation(
    name: 'level.lint',
    summary:
        'Check a level loads and, optionally, that every entity is reachable from the spawn.',
    description:
        'Always checks structure like the engine loader. With `playable:true` it also walks, falls and jumps over the '
        'tileMap from the spawn (a positioned entity named with "player" or "spawn") to every other positioned entity - '
        'the same heuristic the studio validator uses. A conservative model, not a physics simulation: it can pass a '
        'level that needs wall jumps or ladders. `ok` is false when something fails; `problems` says what.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('path', ParamType.path, positional: true),
      Param('json', ParamType.json, cliFlag: 'inline-json'),
      Param('playable', ParamType.boolean, defaultValue: false),
    ],
    handler: (ctx, a) {
      final Map<String, dynamic> json;
      try {
        json = (jsonDecode(levelText(ctx, a)) as Map).cast<String, dynamic>();
      } on FormatException catch (e) {
        return OpOutcome.data({
          'ok': false,
          'problems': ['Not valid JSON: ${e.message}'],
        });
      }
      final List<Map<String, dynamic>> entities;
      try {
        entities = Level.validate(json);
      } on LevelLoadException catch (e) {
        return OpOutcome.data({
          'ok': false,
          'problems': [e.message],
        });
      }
      final problems = <String>[];
      var message = 'OK (${entities.length} entities)';
      Object? unreachable;
      if (a['playable'] == true) {
        final r = _playable(entities);
        problems.addAll(r.problems);
        message = r.problems.isEmpty ? r.message : message;
        unreachable = r.unreachable;
      }
      return OpOutcome.data({
        'ok': problems.isEmpty,
        'message': message,
        'problems': problems,
        'entities': entities.length,
        if (unreachable != null) 'unreachable': unreachable,
      });
    },
  ),
];

class _Playable {
  _Playable(this.problems, this.message, [this.unreachable]);
  final List<String> problems;
  final String message;
  final List<String>? unreachable;
}

_Playable _playable(List<Map<String, dynamic>> entities) {
  Map<String, dynamic>? tileMapJson;
  final positioned = <(String, double, double)>[];
  for (final entity in entities) {
    final components =
        entity['components'] as Map<String, dynamic>? ?? const {};
    final position = components['position'] as Map<String, dynamic>?;
    final tileMap = components['tileMap'] as Map<String, dynamic>?;
    if (tileMap != null) tileMapJson = tileMap;
    if (position != null) {
      positioned.add((
        entity['name'] as String? ?? '<unnamed>',
        (position['x'] as num).toDouble(),
        (position['y'] as num).toDouble(),
      ));
    }
  }
  if (tileMapJson == null) {
    return _Playable(['playable needs a "tileMap" component; none found.'], '');
  }
  final map = TileMap.fromJson(tileMapJson);
  final spawnIndex = positioned.indexWhere(
    (e) =>
        e.$1.toLowerCase().contains('player') ||
        e.$1.toLowerCase().contains('spawn'),
  );
  if (spawnIndex == -1) {
    return _Playable([
      'playable found no spawn entity (a positioned entity with "player" or "spawn" in its name).',
    ], '');
  }
  final spawn = positioned[spawnIndex];
  final onSolid = !isTileReachable(
    map,
    startX: spawn.$2,
    startY: spawn.$3,
    targetX: spawn.$2,
    targetY: spawn.$3,
  );
  if (onSolid) {
    return _Playable(['Spawn entity "${spawn.$1}" sits on a solid tile.'], '');
  }
  final unreachable = <String>[
    for (var i = 0; i < positioned.length; i++)
      if (i != spawnIndex &&
          !isTileReachable(
            map,
            startX: spawn.$2,
            startY: spawn.$3,
            targetX: positioned[i].$2,
            targetY: positioned[i].$3,
          ))
        positioned[i].$1,
  ];
  if (unreachable.isNotEmpty) {
    return _Playable(
      [
        '${unreachable.length} entity(ies) unreachable from spawn "${spawn.$1}": ${unreachable.join(', ')}',
      ],
      '',
      unreachable,
    );
  }
  return _Playable(
    const [],
    'OK (all ${positioned.length - 1} other entities reachable from "${spawn.$1}")',
    const [],
  );
}
