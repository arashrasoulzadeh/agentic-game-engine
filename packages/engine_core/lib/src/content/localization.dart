/// Localization system for multi-language support.
/// Supports language switching, RTL, pluralization, and ICU message format.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';

/// Supported locales with their display names and RTL info.
class LocaleInfo {
  final String code; // e.g., 'en', 'ar', 'zh_CN'
  final String name; // Native name
  final String englishName; // English name
  final bool isRTL;
  final String? fontFamily; // Optional font override

  const LocaleInfo({
    required this.code,
    required this.name,
    required this.englishName,
    this.isRTL = false,
    this.fontFamily,
  });

  /// Common locales with built-in info
  static const Map<String, LocaleInfo> common = {
    'en': LocaleInfo(code: 'en', name: 'English', englishName: 'English'),
    'es': LocaleInfo(code: 'es', name: 'Español', englishName: 'Spanish'),
    'fr': LocaleInfo(code: 'fr', name: 'Français', englishName: 'French'),
    'de': LocaleInfo(code: 'de', name: 'Deutsch', englishName: 'German'),
    'it': LocaleInfo(code: 'it', name: 'Italiano', englishName: 'Italian'),
    'pt': LocaleInfo(code: 'pt', name: 'Português', englishName: 'Portuguese'),
    'pt_BR': LocaleInfo(code: 'pt_BR', name: 'Português (Brasil)', englishName: 'Portuguese (Brazil)'),
    'ru': LocaleInfo(code: 'ru', name: 'Русский', englishName: 'Russian'),
    'ja': LocaleInfo(code: 'ja', name: '日本語', englishName: 'Japanese'),
    'ko': LocaleInfo(code: 'ko', name: '한국어', englishName: 'Korean'),
    'zh': LocaleInfo(code: 'zh', name: '中文', englishName: 'Chinese (Simplified)'),
    'zh_TW': LocaleInfo(code: 'zh_TW', name: '繁體中文', englishName: 'Chinese (Traditional)'),
    'ar': LocaleInfo(code: 'ar', name: 'العربية', englishName: 'Arabic', isRTL: true),
    'he': LocaleInfo(code: 'he', name: 'עברית', englishName: 'Hebrew', isRTL: true),
    'fa': LocaleInfo(code: 'fa', name: 'فارسی', englishName: 'Persian', isRTL: true),
    'hi': LocaleInfo(code: 'hi', name: 'हिन्दी', englishName: 'Hindi'),
    'th': LocaleInfo(code: 'th', name: 'ไทย', englishName: 'Thai'),
    'vi': LocaleInfo(code: 'vi', name: 'Tiếng Việt', englishName: 'Vietnamese'),
    'tr': LocaleInfo(code: 'tr', name: 'Türkçe', englishName: 'Turkish'),
    'pl': LocaleInfo(code: 'pl', name: 'Polski', englishName: 'Polish'),
    'nl': LocaleInfo(code: 'nl', name: 'Nederlands', englishName: 'Dutch'),
    'sv': LocaleInfo(code: 'sv', name: 'Svenska', englishName: 'Swedish'),
    'da': LocaleInfo(code: 'da', name: 'Dansk', englishName: 'Danish'),
    'nb': LocaleInfo(code: 'nb', name: 'Norsk', englishName: 'Norwegian'),
    'fi': LocaleInfo(code: 'fi', name: 'Suomi', englishName: 'Finnish'),
    'cs': LocaleInfo(code: 'cs', name: 'Čeština', englishName: 'Czech'),
    'hu': LocaleInfo(code: 'hu', name: 'Magyar', englishName: 'Hungarian'),
    'ro': LocaleInfo(code: 'ro', name: 'Română', englishName: 'Romanian'),
    'el': LocaleInfo(code: 'el', name: 'Ελληνικά', englishName: 'Greek'),
    'id': LocaleInfo(code: 'id', name: 'Bahasa Indonesia', englishName: 'Indonesian'),
    'ms': LocaleInfo(code: 'ms', name: 'Bahasa Melayu', englishName: 'Malay'),
    'fil': LocaleInfo(code: 'fil', name: 'Filipino', englishName: 'Filipino'),
  };

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'englishName': englishName,
        'isRTL': isRTL,
        'fontFamily': fontFamily,
      };

  factory LocaleInfo.fromJson(Map<String, dynamic> json) => LocaleInfo(
        code: json['code'] as String,
        name: json['name'] as String,
        englishName: json['englishName'] as String,
        isRTL: json['isRTL'] as bool? ?? false,
        fontFamily: json['fontFamily'] as String?,
      );
}

/// A localized string resource with pluralization support.
class LocalizedString {
  final String key;
  final Map<String, String> translations; // locale code -> translation
  final String? defaultLocale;
  final Map<String, Map<int, String>>? pluralForms; // locale -> (count -> translation)

  LocalizedString({
    required this.key,
    required this.translations,
    this.defaultLocale = 'en',
    this.pluralForms,
  });

  /// Get translation for [locale], falling back to [defaultLocale].
  String translate(String locale) {
    return translations[locale] ?? translations[defaultLocale] ?? key;
  }

  /// Get pluralized translation for [count] in [locale].
  String translatePlural(String locale, int count) {
    final forms = pluralForms?[locale] ?? pluralForms?[defaultLocale];
    if (forms != null) {
      // Find matching plural form (exact match or fallback)
      return forms[count] ?? forms.values.firstWhere(
        (v) => true,
        orElse: () => translate(locale),
      );
    }
    return translate(locale);
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'translations': translations,
        'defaultLocale': defaultLocale,
        'pluralForms': pluralForms?.map((k, v) => MapEntry(k, v)),
      };

  factory LocalizedString.fromJson(Map<String, dynamic> json) => LocalizedString(
        key: json['key'] as String,
        translations: (json['translations'] as Map).map(
          (k, v) => MapEntry(k as String, v as String),
        ),
        defaultLocale: json['defaultLocale'] as String? ?? 'en',
        pluralForms: (json['pluralForms'] as Map?)?.map(
          (k, v) => MapEntry(
            k as String,
            (v as Map).map((k2, v2) => MapEntry(int.parse(k2 as String), v2 as String)),
          ),
        ),
      );
}

class LocalizationManager {
  final Map<String, LocalizedString> _resources = {};
  final List<LocaleInfo> _availableLocales = [];
  String _currentLocale = 'en';
  String _fallbackLocale = 'en';
  final Map<String, String> _customLocales = {};

  /// Called when locale changes.
  void Function(String newLocale)? onLocaleChanged;

  /// Private constructor for singleton.
  LocalizationManager._();

  /// Singleton instance.
  static final LocalizationManager _instance = LocalizationManager._();
  static LocalizationManager get instance => _instance;

  /// Current active locale.
  String get currentLocale => _currentLocale;

  /// Whether current locale is RTL.
  bool get isRTL => LocaleInfo.common[currentLocale]?.isRTL ?? false;

  /// All available locales.
  List<LocaleInfo> get availableLocales => List.unmodifiable(_availableLocales);

  /// Add a resource file (JSON/CSV/ARB).
  Future<void> addResource(LocalizedString resource) {
    _resources[resource.key] = resource;
    return Future.value();
  }

  /// Load resources from a JSON file.
  Future<void> loadFromJson(String jsonString) async {
    final map = json.decode(jsonString) as Map<String, dynamic>;
    for (final entry in map.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is Map) {
        final resource = LocalizedString.fromJson({
          'key': key,
          ...value,
        });
        await addResource(resource);
      }
    }
  }

  /// Load resources from a directory of JSON files.
  Future<void> loadFromDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return;

    await for (final file in dir.list()) {
      if (file is File && file.path.endsWith('.json')) {
        final content = await file.readAsString();
        await loadFromJson(content);
      }
    }
  }

  /// Add a locale.
  void addLocale(LocaleInfo locale) {
    if (!_availableLocales.any((l) => l.code == locale.code)) {
      _availableLocales.add(locale);
    }
  }

  /// Set current locale.
  void setLocale(String localeCode) {
    if (!_availableLocales.any((l) => l.code == localeCode)) {
      // Allow custom locales too
    }
    if (_currentLocale != localeCode) {
      _currentLocale = localeCode;
      onLocaleChanged?.call(localeCode);
    }
  }

  /// Get translation for key.
  String tr(String key, {Map<String, dynamic>? args}) {
    final resource = _resources[key];
    if (resource == null) return key;
    String result = resource.translate(_currentLocale);
    if (args != null) {
      for (final entry in args.entries) {
        result = result.replaceAll('{${entry.key}}', entry.value.toString());
      }
    }
    return result;
  }

  /// Get pluralized translation.
  String trPlural(String key, int count, {Map<String, dynamic>? args}) {
    final resource = _resources[key];
    if (resource == null) return key;
    String result = resource.translatePlural(_currentLocale, count);
    if (args != null) {
      for (final entry in args.entries) {
        result = result.replaceAll('{${entry.key}}', entry.value.toString());
      }
    }
    return result;
  }

  /// Get locale info for current locale.
  LocaleInfo? get currentLocaleInfo {
    return LocaleInfo.common[_currentLocale];
  }

  /// Set fallback locale.
  void setFallbackLocale(String localeCode) {
    _fallbackLocale = localeCode;
  }

  /// Get all available locale codes.
  List<String> get availableLocaleCodes => _availableLocales.map((l) => l.code).toList();
}

/// Extension for easy translation.
extension Localization on String {
  String tr([Map<String, dynamic>? args]) {
    return LocalizationManager.instance.tr(this, args: args);
  }

  String trPlural(int count, [Map<String, dynamic>? args]) {
    return LocalizationManager.instance.trPlural(this, count, args: args);
  }
}

/// Singleton instance.
class _LocalizationManagerSingleton {
  static final LocalizationManager _instance = LocalizationManager._();
  static LocalizationManager get instance => _instance;
}