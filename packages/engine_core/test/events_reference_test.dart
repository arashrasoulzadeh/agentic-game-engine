import 'dart:io';

import 'package:test/test.dart';

/// docs/reference/events.md is hand-written. This keeps it from drifting: every
/// public event class anywhere in the repo's packages must be named in it.
void main() {
  test('every public *Event class is listed in docs/reference/events.md', () {
    final packages = Directory('..');
    final doc = File('../../docs/reference/events.md').readAsStringSync();
    final declared = RegExp(
      r'^(?:final |base |abstract |sealed )*class ([A-Z]\w*Event)\b',
      multiLine: true,
    );
    final found = <String, String>{};
    for (final pkg in packages.listSync().whereType<Directory>()) {
      final lib = Directory('${pkg.path}/lib');
      if (!lib.existsSync()) continue;
      for (final f in lib.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        for (final m in declared.allMatches(f.readAsStringSync())) {
          found[m.group(1)!] = f.path;
        }
      }
    }
    expect(found, isNotEmpty);
    final missing = [
      for (final e in found.entries)
        if (!doc.contains('`${e.key}`')) '${e.key} (${e.value})',
    ];
    expect(missing, isEmpty, reason: 'add these to docs/reference/events.md');
  });
}
