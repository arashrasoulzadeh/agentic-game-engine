import 'dart:io';

import 'package:engine_api/engine_api.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void main() {
  test('docs/reference/operations.md is up to date with the registry', () {
    final committed = File('../../docs/reference/operations.md').readAsStringSync();
    expect(
      committed,
      renderOperationsReference(buildRegistry()),
      reason:
          'Regenerate it: cd packages/engine_api && dart run tool/gen_api_docs.dart > ../../docs/reference/operations.md',
    );
  });

  test('every operation has a section and Flutter-only ones say so', () {
    final text = renderOperationsReference(buildRegistry());
    for (final op in buildRegistry().all) {
      expect(text, contains('### `${op.name}`'));
    }
    expect(text, contains('CLI only (needs the Flutter SDK)'));
  });
}
