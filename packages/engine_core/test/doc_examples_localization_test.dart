// The samples in docs/concepts/localization.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  final i18n = LocalizationManager.instance;

  tearDown(() {
    i18n.setLocale('en');
    i18n.setFallbackLocale('en');
  });

  test('load strings from JSON, switch language, substitute arguments', () async {
    await i18n.loadFromJson('''
{
  "menu.start": { "translations": { "en": "Start", "fr": "Commencer", "ar": "ابدأ" } },
  "hud.score":  { "translations": { "en": "Score: {points}", "fr": "Score : {points}" } },
  "hud.only_en": { "translations": { "en": "English only" } }
}
''');

    expect('menu.start'.tr(), 'Start');
    i18n.setLocale('fr');
    expect('menu.start'.tr(), 'Commencer');
    expect('hud.score'.tr({'points': 120}), 'Score : 120');

    // A string with no French falls back to English; an unknown key returns itself.
    expect('hud.only_en'.tr(), 'English only');
    expect('no.such.key'.tr(), 'no.such.key');
  });

  test('right-to-left languages are reported from the locale table', () async {
    await i18n.loadFromJson('{"a": {"translations": {"en": "x", "ar": "y"}}}');
    i18n.setLocale('ar');
    expect(i18n.isRTL, isTrue);
    i18n.setLocale('en');
    expect(i18n.isRTL, isFalse);
  });

  test(
    'plurals: exact counts per language, first form as the fallback',
    () async {
      await i18n.addResource(
        LocalizedString(
          key: 'items',
          translations: {'en': 'items'},
          pluralForms: {
            'en': {0: 'No items', 1: 'One item', 5: '{count} items'},
          },
        ),
      );
      expect(i18n.trPlural('items', 1), 'One item');
      expect(i18n.trPlural('items', 5, args: {'count': 5}), '5 items');
      // A count with no form of its own gets the first one listed -- there are no
      // CLDR plural rules, so list every count you need.
      expect(i18n.trPlural('items', 3), 'No items');
    },
  );

  test('locale changes notify a listener', () {
    final seen = <String>[];
    i18n.onLocaleChanged = seen.add;
    i18n.setLocale('de');
    i18n.setLocale('de');
    i18n.setLocale('en');
    i18n.onLocaleChanged = null;
    expect(seen, ['de', 'en']);
  });
}
