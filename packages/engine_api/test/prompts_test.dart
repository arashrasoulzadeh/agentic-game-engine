import 'package:engine_api/engine_api.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  final registry = buildRegistry();

  test('every operation a prompt mentions exists', () {
    final pattern = RegExp(r'`([a-z_]+\.[a-z_]+)`');
    for (final p in enginePrompts) {
      for (final m in pattern.allMatches(p.template)) {
        expect(
          registry.lookup(m[1]!),
          isNotNull,
          reason: '${p.name} names ${m[1]}',
        );
      }
    }
  });

  test('prompts/list and prompts/get render arguments', () async {
    final s = McpSession(registry, OpContext());
    final list = await s.dispatch('prompts/list', {}) as Map;
    expect(
      (list['prompts'] as List).map((p) => (p as Map)['name']),
      contains('build_level'),
    );
    final got =
        await s.dispatch('prompts/get', {
              'name': 'build_level',
              'arguments': {'path': 'assets/levels/x.json', 'theme': 'forest'},
            })
            as Map;
    final text =
        ((got['messages'] as List).single as Map)['content']['text'] as String;
    expect(text, contains('assets/levels/x.json'));
    expect(text, contains('forest'));
    expect(text, isNot(contains('{{')));
  });

  test('a missing required argument or an unknown prompt is -32602', () async {
    final s = McpSession(registry, OpContext());
    await expectLater(
      s.dispatch('prompts/get', {'name': 'build_level'}),
      throwsA(isA<RpcException>().having((e) => e.code, 'code', -32602)),
    );
    await expectLater(
      s.dispatch('prompts/get', {'name': 'nope'}),
      throwsA(isA<RpcException>().having((e) => e.code, 'code', -32602)),
    );
  });
}
