/// Localized strings, keyed by id then by locale — a small, standalone
/// primitive a game calls to resolve *what text to show*, independent
/// of `Text`/anything that actually renders it (single responsibility:
/// `Text` renders a string, `StringTable` decides which string). JSON-
/// authorable directly, same "content as data" pattern as `Level`:
/// `{"greeting": {"en": "Hello, {name}!", "es": "¡Hola, {name}!"}}`.
///
/// Font-fallback for scripts a bundled custom font doesn't cover is
/// deliberately out of scope here — that's an asset/font-selection
/// concern (which font a `Text` uses, or Flutter's own system-font
/// fallback), not a string-lookup one; this only ever hands back a
/// `String`, never touches rendering.
class StringTable {
  final Map<String, Map<String, String>> _entries;
  final String defaultLocale;
  String _locale;

  StringTable(
    Map<String, Map<String, String>> entries, {
    this.defaultLocale = 'en',
    String? locale,
  })  : _entries = entries,
        _locale = locale ?? defaultLocale;

  /// The active locale every [resolve] call uses unless a key has no
  /// entry for it. Not validated against [_entries] — switching to a
  /// locale nothing has translations for yet is allowed and just falls
  /// back to [defaultLocale] per-key, useful while a translation pass
  /// is still in progress.
  String get locale => _locale;
  set locale(String value) => _locale = value;

  /// Resolves [key] for the active [locale]: that locale's string if
  /// present, else [defaultLocale]'s, else [key] itself — a missing
  /// translation reads as a visible, debuggable raw key in-game rather
  /// than silently showing blank or throwing, the same "doesn't hide
  /// how it works" philosophy the rest of this engine follows.
  ///
  /// [params], if given, does simple `{name}`-style substitution on
  /// the resolved string — enough for "Hello, {name}!"/"{count} coins"
  /// without pulling in a real ICU pluralization/formatting library
  /// nothing has asked for yet.
  String resolve(String key, {Map<String, String>? params}) {
    final forKey = _entries[key];
    var text = forKey?[_locale] ?? forKey?[defaultLocale] ?? key;
    if (params != null) {
      for (final entry in params.entries) {
        text = text.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return text;
  }

  /// Whether [key] has an entry for the active [locale] specifically
  /// (not counting a [defaultLocale] fallback) — lets a game flag
  /// missing translations (e.g. in a debug overlay) instead of only
  /// ever seeing the silent fallback [resolve] gives.
  bool hasTranslation(String key) => _entries[key]?.containsKey(_locale) ?? false;

  Map<String, dynamic> toJson() => {
        'defaultLocale': defaultLocale,
        'entries': _entries,
      };

  factory StringTable.fromJson(Map<String, dynamic> json, {String? locale}) {
    final rawEntries = (json['entries'] as Map?)?.cast<String, dynamic>() ?? const {};
    final entries = <String, Map<String, String>>{};
    rawEntries.forEach((key, value) {
      entries[key] = (value as Map).cast<String, String>();
    });
    return StringTable(
      entries,
      defaultLocale: json['defaultLocale'] as String? ?? 'en',
      locale: locale,
    );
  }
}
