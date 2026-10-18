# Localization

`LocalizationManager` (in `engine_core`) holds your game's text in every language and
returns the right one for the active locale. It is a singleton, so any code — a system, a
dialogue box, a menu — can look text up without being passed a manager.

Everything below is executed by
`packages/engine_core/test/doc_examples_localization_test.dart`.

## Strings

Strings are JSON, keyed by an id you choose, with one entry per language:

```dart
final i18n = LocalizationManager.instance;

await i18n.loadFromJson('''
{
  "menu.start": { "translations": { "en": "Start", "fr": "Commencer", "ar": "ابدأ" } },
  "hud.score":  { "translations": { "en": "Score: {points}", "fr": "Score : {points}" } },
  "hud.only_en": { "translations": { "en": "English only" } }
}
''');

'menu.start'.tr();                 // "Start"
i18n.setLocale('fr');
'menu.start'.tr();                 // "Commencer"
'hud.score'.tr({'points': 120});   // "Score : 120"
```

- `'key'.tr([args])` is shorthand for `LocalizationManager.instance.tr(key, args: args)`.
  `{name}` placeholders are replaced from `args`.
- A string with no translation in the active language falls back to English (change the
  fallback with `setFallbackLocale`); a key that does not exist returns the key itself, so a
  missing string is visible on screen instead of crashing.
- `loadFromDirectory(path)` loads every `*.json` file in a folder (not on web: it uses
  `dart:io`). Use `loadFromJson` with `rootBundle.loadString(...)` there.

!!! note "Formats"
    JSON is the only file format. CSV and ARB are not implemented; convert them to this
    JSON shape in your build.

## Switching language

`setLocale('fr')` changes the active language and calls `onLocaleChanged` (if set) — but only
when the locale actually changes, so it is safe to call every frame. Re-read your strings when
it fires; the manager does not push updates into text that is already on screen.

```dart
i18n.onLocaleChanged = (code) => rebuildMenus();
```

In a Flutter game, `LocalizationFlutter` (in `engine_flutter`) wraps the same manager and adds
`initialize(supportedLocales: ..., initialLocale: ...)`, `textDirection`, `rtlAwareAlign` and
`localeTextStyle` (which applies a locale's font override).

## Right to left

`LocaleInfo.common` knows about 32 locales, including their native names and which are
right-to-left (Arabic, Hebrew, Persian). `i18n.isRTL` reflects the active locale. The engine
does not mirror your layout for you: use `isRTL` / `LocalizationFlutter.textDirection` in the
UI code that lays out text.

## Plurals

Give a string `pluralForms` per language, keyed by **exact count**:

```dart
await i18n.addResource(LocalizedString(
  key: 'items',
  translations: {'en': 'items'},
  pluralForms: {
    'en': {0: 'No items', 1: 'One item', 5: '{count} items'},
  },
));

i18n.trPlural('items', 1);                         // "One item"
i18n.trPlural('items', 5, args: {'count': 5});     // "5 items"
i18n.trPlural('items', 3);                         // "No items"  (first form listed)
```

There are no CLDR plural rules (few/many/other): a count with no form of its own gets the
first form in the map, so list every count you need, or lead with your general form. In JSON
the count keys are strings (`"pluralForms": {"en": {"1": "One item"}}`).

## In the studio

The studio uses the same manager for its own interface text — see the
[user guide](../studio/user-guide.md#settings).
