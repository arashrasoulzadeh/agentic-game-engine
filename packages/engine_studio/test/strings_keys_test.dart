import 'dart:io';

import 'package:engine_studio/src/prefs/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every key the studio looks up exists in the English catalog', () {
    final used = <String, String>{};
    final pattern = RegExp(r"StudioStrings\.t\(\s*'([^']+)'");
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      for (final m in pattern.allMatches(f.readAsStringSync())) {
        used[m.group(1)!] = f.path;
      }
    }
    expect(used, isNotEmpty);
    final missing = {
      for (final e in used.entries)
        if (!StudioStrings.english.containsKey(e.key)) e.key: e.value,
    };
    expect(
      missing,
      isEmpty,
      reason: 'a missing key shows as the bare key to players',
    );
  });

  test('a translated key reaches the screens that were migrated', () {
    final dir = Directory.systemTemp.createTempSync('studio_locale');
    addTearDown(() {
      dir.deleteSync(recursive: true);
      StudioStrings.use('en');
    });
    File('${dir.path}/fa.json').writeAsStringSync('{"level.save": "ذخیره"}');
    StudioStrings.use('fa', localesDir: dir);
    expect(StudioStrings.t('level.save'), 'ذخیره');
    expect(
      StudioStrings.t('level.showGrid'),
      'Show grid',
      reason: 'untranslated falls back to English',
    );
  });
}
