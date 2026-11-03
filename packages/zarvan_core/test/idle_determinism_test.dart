import 'dart:io';

import 'package:test/test.dart';

/// Idle simulation must be reproducible: time enters only through arguments (`OfflineProgress`'s
/// `now`, the session's injectable clock) and randomness only through `DeterministicRandom`. A stray
/// `DateTime.now()` or `Random()` in the rules would make offline catch-up, the balance simulator and
/// replays disagree with themselves, so this fails when one is added.
void main() {
  test(
    'the idle rules and content maths never read the wall clock or an unseeded Random',
    () {
      final files = [
        ...Directory('lib/src/idle').listSync().whereType<File>(),
        for (final n in [
          'big_number',
          'big_treasury',
          'offline_progress',
          'cost_curve',
          'modifier_stack',
          'save_codec',
          'number_format',
        ])
          File('lib/src/content/$n.dart'),
      ];
      expect(files.length, greaterThan(10));
      final offenders = <String>[];
      for (final f in files) {
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        if (RegExp(r'DateTime\.now\(|\bRandom\(|Stopwatch\(').hasMatch(code)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
    },
  );
}
