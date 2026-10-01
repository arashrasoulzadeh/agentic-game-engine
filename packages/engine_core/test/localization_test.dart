import 'package:engine_core/src/content/localization.dart';
import 'package:test/test.dart';

void main() {
  group('LocalizationManager fallback locale', () {
    late LocalizationManager manager;

    setUp(() async {
      manager = LocalizationManager.instance;
      await manager.addResource(LocalizedString(
        key: 'greeting',
        translations: {'en': 'Hello', 'fr': 'Bonjour'},
      ));
      manager.setLocale('en');
      manager.setFallbackLocale('en');
    });

    test('uses current locale translation when present', () {
      manager.setLocale('fr');
      expect(manager.tr('greeting'), 'Bonjour');
    });

    test('falls back to the configured fallback locale, not just the '
        "resource's own default, when current locale is missing", () {
      // "de" has no translation and isn't the resource's defaultLocale
      // ("en", same as the manager's configured fallback here) — but set
      // the manager's fallback to "fr" specifically to prove *that* path
      // is consulted, not just LocalizedString.translate's own default.
      manager.setFallbackLocale('fr');
      manager.setLocale('de');
      expect(manager.tr('greeting'), 'Bonjour');
    });

    test('falls back to the resource\'s own default locale when neither '
        "current nor the manager's fallback locale exist", () {
      manager.setFallbackLocale('es');
      manager.setLocale('de');
      // LocalizedString.defaultLocale is 'en' and that's still present.
      expect(manager.tr('greeting'), 'Hello');
    });

    test('falls back to the key as a last resort when nothing matches', () async {
      await manager.addResource(LocalizedString(
        key: 'untranslated',
        translations: {'fr': 'Bonjour'},
        defaultLocale: 'ja',
      ));
      manager.setFallbackLocale('es');
      manager.setLocale('de');
      expect(manager.tr('untranslated'), 'untranslated');
    });
  });
}
