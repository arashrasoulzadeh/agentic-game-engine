import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:path/path.dart' as p;

/// The studio's own text, looked up by key so it can be translated.
///
/// English lives here as the source of truth: a key with no translation (or a
/// translation file that is missing or broken) shows English, never a bare key. Other
/// languages are `<code>.json` files of `{ "key": "text" }` in the user's
/// `~/.game_agent/locales` folder, chosen by `locale` in `studio_prefs.json`; they are
/// registered through the engine's own [LocalizationManager], so the studio and games
/// share one mechanism. Screens are migrated to [t] incrementally; text that has not
/// been moved yet simply stays English.
class StudioStrings {
  StudioStrings._();

  static const Map<String, String> english = {
    'project.assets': 'Assets: sprite sheets, images, audio, prefabs',
    'project.newGraph': 'New graph',
    'project.newGraph.dialogue': 'Dialogue / cutscene graph',
    'project.newGraph.behaviorTree': 'Behavior tree',
    'project.newGraph.stateMachine': 'State machine',
    'project.problems': 'Problems in levels and graphs',
    'project.search': 'Find in project (Cmd/Ctrl+Shift+F)',
    'project.close': 'Close',
    'project.noFile': 'Pick a file on the left to open it.',
    'project.fileGone': 'That file no longer exists.',
  };

  static bool _registered = false;

  static final LocalizationManager _manager = LocalizationManager.instance;

  static void _registerEnglish() {
    if (_registered) return;
    _registered = true;
    _manager.setFallbackLocale('en');
    for (final e in english.entries) {
      _manager.addResource(
        LocalizedString(key: e.key, translations: {'en': e.value}),
      );
    }
  }

  /// The text for [key] in the active language, falling back to English, then to
  /// [key] itself for a key the studio does not know.
  static String t(String key, [Map<String, dynamic>? args]) {
    _registerEnglish();
    return _manager.tr(key, args: args);
  }

  /// Activates [locale]. When [localesDir] has `<locale>.json`, its entries override
  /// the English for that language. A missing locale file is not an error: the studio
  /// stays usable, in English.
  static void use(String locale, {Directory? localesDir}) {
    _registerEnglish();
    if (locale != 'en' && localesDir != null) {
      final file = File(p.join(localesDir.path, '$locale.json'));
      try {
        if (file.existsSync()) {
          final json = jsonDecode(file.readAsStringSync());
          if (json is Map) {
            for (final e in json.entries) {
              final key = e.key as String;
              final value = e.value;
              if (value is! String || !english.containsKey(key)) continue;
              _manager.addResource(
                LocalizedString(
                  key: key,
                  translations: {'en': english[key]!, locale: value},
                ),
              );
            }
          }
        }
      } on Object {
        // A broken translation file leaves English in place.
      }
    }
    _manager.setLocale(locale);
  }

  /// Whether the active language is written right to left.
  static bool get isRtl => _manager.isRTL;
}

/// Where the user's translation files live, next to the studio prefs.
Directory studioLocalesDir({Map<String, String>? env}) {
  final e = env ?? Platform.environment;
  final home = e['HOME'] ?? e['USERPROFILE'] ?? '.';
  return Directory(p.join(home, '.game_agent', 'locales'));
}
