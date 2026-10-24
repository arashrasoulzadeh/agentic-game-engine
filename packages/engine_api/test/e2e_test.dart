import 'dart:convert';
import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

/// The whole agent workflow through one MCP session: open a project, build a level, validate, simulate the world,
/// delete with a confirmation, and undo. Confirmation tokens are bound to the server process, so it is one session.
void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync('e2e');
    File(
      '${project.path}/pubspec.yaml',
    ).writeAsStringSync('name: e2e_game\nversion: 0.0.1\n');
    Directory('${project.path}/assets/levels').createSync(recursive: true);
  });
  tearDown(() => project.deleteSync(recursive: true));

  test(
    'an agent builds, checks, simulates, deletes and undoes - all through MCP tools',
    () async {
      final session = McpSession(buildRegistry(), OpContext());
      Future<Map> tool(String name, Map<String, Object?> args) async {
        final r =
            await session.dispatch('tools/call', {
                  'name': name,
                  'arguments': args,
                })
                as Map;
        return r['structuredContent'] as Map;
      }

      Future<dynamic> ok(String name, Map<String, Object?> args) async {
        final e = await tool(name, args);
        expect(e['ok'], isTrue, reason: '$name: $e');
        return e['data'];
      }

      const lv = 'assets/levels/e2e.json';
      expect(
        (await ok('project.open', {'path': project.path}))['name'],
        'e2e_game',
      );
      await ok('level.create', {'path': lv});
      await ok('level.add_entity', {
        'path': lv,
        'name': 'player',
        'components': ['position', 'velocity'],
      });
      await ok('level.set_field', {
        'path': lv,
        'entity': 'player',
        'component': 'velocity',
        'field': 'x',
        'value': 30,
      });
      expect((await ok('level.validate', {'path': lv}))['ok'], isTrue);

      final built = await ok('world.build', {'path': lv});
      expect(built['entities'], 1);
      await ok('world.step', {'worldId': built['worldId'], 'ticks': 60});
      final q =
          await ok('world.query', {
                'worldId': built['worldId'],
                'component': 'position',
              })
              as dynamic;
      expect(q, isNotEmpty);

      final preview = await ok('level.remove_entity', {
        'path': lv,
        'name': 'player',
      });
      expect(
        preview['confirmation'],
        isA<String>(),
        reason: 'removal previews first',
      );
      expect(
        File('${project.path}/$lv').readAsStringSync(),
        contains('player'),
      );
      await ok('level.remove_entity', {
        'path': lv,
        'name': 'player',
        'confirmation': preview['confirmation'],
      });
      expect(
        File('${project.path}/$lv').readAsStringSync(),
        isNot(contains('player')),
      );

      await ok('undo.undo', {});
      expect(
        File('${project.path}/$lv').readAsStringSync(),
        contains('player'),
        reason: 'undo restored the entity',
      );
      expect(jsonEncode(await ok('undo.list', {})), contains('level.'));
    },
  );
}
