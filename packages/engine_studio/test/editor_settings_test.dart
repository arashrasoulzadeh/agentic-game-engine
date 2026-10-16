import 'dart:io';

import 'package:engine_studio/src/code/editor_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults are font size 13, tab width 2, format-on-save off', () {
    const settings = EditorSettings();
    expect(settings.fontSize, 13);
    expect(settings.tabWidth, 2);
    expect(settings.formatOnSave, isFalse);
  });

  test('toJson/fromJson round-trips every field', () {
    const settings = EditorSettings(
      fontSize: 16,
      tabWidth: 4,
      formatOnSave: true,
    );
    final decoded = EditorSettings.fromJson(settings.toJson());
    expect(decoded.fontSize, 16);
    expect(decoded.tabWidth, 4);
    expect(decoded.formatOnSave, isTrue);
  });

  test('copyWith changes only the given fields', () {
    const settings = EditorSettings(fontSize: 16, tabWidth: 4);
    final updated = settings.copyWith(formatOnSave: true);
    expect(updated.fontSize, 16);
    expect(updated.tabWidth, 4);
    expect(updated.formatOnSave, isTrue);
  });

  group('fromJson with bad input', () {
    test('a missing field falls back to its default', () {
      final decoded = EditorSettings.fromJson({'fontSize': 20});
      expect(decoded.fontSize, 20);
      expect(decoded.tabWidth, 2);
      expect(decoded.formatOnSave, isFalse);
    });

    test('a field of the wrong type falls back to its default instead of throwing', () {
      final decoded = EditorSettings.fromJson({
        'fontSize': 'not a number',
        'tabWidth': true,
        'formatOnSave': 5,
      });
      expect(decoded.fontSize, 13);
      expect(decoded.tabWidth, 2);
      expect(decoded.formatOnSave, isFalse);
    });
  });

  group('EditorSettingsStore', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('editor_settings'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('reading with nothing saved yet gives the defaults', () {
      final store = EditorSettingsStore(dir.path);
      expect(store.read().fontSize, 13);
    });

    test('a write is read back exactly, under .studio/', () {
      final store = EditorSettingsStore(dir.path);
      store.write(const EditorSettings(fontSize: 18, tabWidth: 4, formatOnSave: true));

      final file = File('${dir.path}/.studio/editor_settings.json');
      expect(file.existsSync(), isTrue);

      final read = store.read();
      expect(read.fontSize, 18);
      expect(read.tabWidth, 4);
      expect(read.formatOnSave, isTrue);
    });

    test('a corrupted settings file falls back to defaults rather than throwing', () {
      final file = File('${dir.path}/.studio/editor_settings.json')
        ..createSync(recursive: true);
      file.writeAsStringSync('{ not json');
      final store = EditorSettingsStore(dir.path);
      expect(() => store.read(), returnsNormally);
      expect(store.read().fontSize, 13);
    });
  });
}
