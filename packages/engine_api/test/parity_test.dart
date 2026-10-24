import 'package:engine_api/engine_api.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

/// The 1:1 rule: every served operation is an MCP tool, a REST path and a JSON-RPC method; the CLI side of the
/// rule is asserted in engine_cli's ops_cli_test, which walks the same registry.
void main() {
  final registry = buildRegistry();
  final served = [
    for (final o in registry.all)
      if (!o.requiresFlutter) o,
  ];

  test('every served operation is an MCP tool and nothing else is', () async {
    final session = McpSession(registry, OpContext());
    final tools = <String>[];
    String? cursor;
    do {
      final r =
          await session.dispatch('tools/list', {
                if (cursor != null) 'cursor': cursor,
              })
              as Map;
      tools.addAll([
        for (final t in r['tools'] as List) (t as Map)['name'] as String,
      ]);
      cursor = r['nextCursor'] as String?;
    } while (cursor != null);
    expect(tools..sort(), [for (final o in served) o.name]..sort());
  });

  test('every served operation has a REST path in the OpenAPI document', () {
    final paths = (openApiFor(served)['paths'] as Map).keys.toSet();
    expect(paths, {for (final o in served) '/v1/${o.group}/${o.verb}'});
  });

  test(
    'operations the server cannot serve are exactly the Flutter-dependent ones',
    () {
      final hidden = registry.all
          .where((o) => o.requiresFlutter)
          .map((o) => o.name)
          .toSet();
      expect(
        hidden,
        containsAll(['project.create', 'project.upgrade', 'release.build']),
      );
      expect(served.length + hidden.length, registry.all.length);
    },
  );

  test(
    'every tool has a description with its kind and an input schema that forbids unknown keys',
    () {
      for (final o in served) {
        final tool = toolFor(o);
        expect(tool['description'], contains('Kind:'), reason: o.name);
        expect(
          (tool['inputSchema'] as Map)['additionalProperties'],
          false,
          reason: o.name,
        );
      }
    },
  );
}
