import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('docs/reference/components.md is up to date with the schemas', () async {
    final result = await Process.run(
      Platform.resolvedExecutable,
      ['run', 'tool/gen_component_docs.dart'],
    );
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final committed = File('../../docs/reference/components.md').readAsStringSync();
    expect(result.stdout, committed,
        reason: 'Regenerate: cd packages/engine_schema && '
            'dart run tool/gen_component_docs.dart > ../../docs/reference/components.md');
  });
}
