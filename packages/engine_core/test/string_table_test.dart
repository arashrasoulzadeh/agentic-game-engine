import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('StringTable', () {
    test('resolves a key for the active locale', () {
      final table = StringTable({
        'greeting': {'en': 'Hello', 'es': 'Hola'},
      }, locale: 'es');
      expect(table.resolve('greeting'), 'Hola');
    });

    test('defaults to defaultLocale when the active locale has no translation', () {
      final table = StringTable({
        'greeting': {'en': 'Hello'},
      }, locale: 'fr');
      expect(table.resolve('greeting'), 'Hello');
    });

    test('falls back to the raw key when neither locale nor defaultLocale has it', () {
      final table = StringTable({}, locale: 'en');
      expect(table.resolve('missingKey'), 'missingKey');
    });

    test('substitutes {param}-style placeholders', () {
      final table = StringTable({
        'welcome': {'en': 'Hello, {name}! You have {count} coins.'},
      });
      expect(
        table.resolve('welcome', params: {'name': 'Ada', 'count': '5'}),
        'Hello, Ada! You have 5 coins.',
      );
    });

    test('locale can be switched at runtime', () {
      final table = StringTable({
        'greeting': {'en': 'Hello', 'es': 'Hola'},
      });
      expect(table.resolve('greeting'), 'Hello');
      table.locale = 'es';
      expect(table.resolve('greeting'), 'Hola');
    });

    test('hasTranslation reflects the active locale specifically, not the defaultLocale fallback', () {
      final table = StringTable({
        'greeting': {'en': 'Hello'},
      }, locale: 'fr');
      expect(table.hasTranslation('greeting'), isFalse);
      table.locale = 'en';
      expect(table.hasTranslation('greeting'), isTrue);
    });

    test('round-trips through toJson/fromJson', () {
      final table = StringTable({
        'greeting': {'en': 'Hello', 'es': 'Hola'},
      }, defaultLocale: 'en', locale: 'es');

      final restored = StringTable.fromJson(table.toJson(), locale: 'es');
      expect(restored.resolve('greeting'), 'Hola');
      expect(restored.defaultLocale, 'en');
    });

    test('fromJson defaults defaultLocale to "en" and locale to defaultLocale when absent', () {
      final restored = StringTable.fromJson({
        'entries': {
          'greeting': {'en': 'Hello'},
        },
      });
      expect(restored.defaultLocale, 'en');
      expect(restored.locale, 'en');
      expect(restored.resolve('greeting'), 'Hello');
    });
  });
}
