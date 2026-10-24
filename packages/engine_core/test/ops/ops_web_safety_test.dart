import 'dart:io';

import 'package:test/test.dart';

/// The operation registry uses dart:io, so it must stay out of the main library, which compiles for the web.
void main() {
  test('engine_core.dart does not export or import anything under src/ops/', () {
    final text = File('lib/engine_core.dart').readAsStringSync();
    expect(text, isNot(contains('src/ops/')));
  });
}
