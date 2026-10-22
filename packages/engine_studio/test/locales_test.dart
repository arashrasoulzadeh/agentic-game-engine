import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/prefs/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final file in Directory(
    'locales',
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
    final code = file.uri.pathSegments.last.replaceAll('.json', '');
    final catalog = (jsonDecode(file.readAsStringSync()) as Map)
        .cast<String, String>();

    test('$code only translates keys the studio has', () {
      final unknown = catalog.keys.where(
        (k) => !StudioStrings.english.containsKey(k),
      );
      expect(
        unknown,
        isEmpty,
        reason: 'a renamed key leaves its translation dead',
      );
    });

    test(
      '$code covers most of the catalog and keeps keyboard hints intact',
      () {
        expect(
          catalog.length / StudioStrings.english.length,
          greaterThan(0.85),
        );
        for (final e in catalog.entries) {
          for (final hint in RegExp(
            r'(Cmd/Ctrl\+[A-Za-z+]+|Shift\+Enter|\(Enter\)|\(Esc\))',
          ).allMatches(StudioStrings.english[e.key]!)) {
            expect(
              e.value,
              contains(hint.group(0)!.replaceAll(RegExp(r'[()]'), '')),
              reason: e.key,
            );
          }
        }
      },
    );

    test('$code keeps every {placeholder} of the English text', () {
      final names = RegExp(r'\{(\w+)\}');
      for (final e in catalog.entries) {
        final want = names
            .allMatches(StudioStrings.english[e.key]!)
            .map((m) => m.group(1))
            .toSet();
        final got = names.allMatches(e.value).map((m) => m.group(1)).toSet();
        expect(got, want, reason: e.key);
      }
    });

    test('$code loads and is used by StudioStrings', () {
      addTearDown(() => StudioStrings.use('en'));
      StudioStrings.use(code, localesDir: Directory('locales'));
      expect(StudioStrings.t('common.cancel'), catalog['common.cancel']);
    });
  }
}
