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
    'validation_panel.this_level_has_no_problems':
        'This level has no problems.',
    'project_screen.find_in_project': 'Find in project',
    'project_open_screen.open': 'Open',
    'project_open_screen.browse': 'Browse…',
    'project_open_screen.game_project_folder': 'Game project folder',
    'project_open_screen.open_project': 'Open project',
    'project_open_screen.no_update_server_configured':
        'No update server configured',
    'image_view.that_image_no_longer_exists': 'That image no longer exists.',
    'preview_view.profiler': 'Profiler',
    'preview_view.fit_width': 'Fit width',
    'preview_view.press_play_to_run_the_level': 'Press play to run the level.',
    'bootstrap_screen.skip': 'Skip',
    'bootstrap_screen.later': 'Later',
    'bootstrap_screen.accept': 'Accept',
    'bootstrap_screen.retry': 'Retry',
    'bootstrap_screen.install_accepted': 'Install accepted',
    'bootstrap_screen.try_again': 'Try again',
    'bootstrap_screen.check_again': 'Check again',
    'bootstrap_screen.updates_and_downloads': 'Updates and downloads',
    'brush_panel.delete_brush': 'Delete brush',
    'brush_panel.no_brushes_yet': 'No brushes yet.',
    'brush_panel.save_as_prefab': 'Save as prefab',
    'brush_panel.new_tile_brush': 'New tile brush',
    'brush_panel.brushes': 'Brushes',
    'atlas_view.pick_a_sprite': 'Pick a sprite',
    'code.formatOnSave': 'Format on save',
    'code.rename': 'Rename',
    'code.renameTitle': 'Rename symbol',
    'code.settings': 'Editor settings',
    'code.analyze': 'Analyze project (compile check)',
    'code.outline': 'Document outline',
    'code.discard': 'Discard',
    'code.discardTitle': 'Discard unsaved changes?',
    'code.replaceAll': 'Replace All',
    'code.replace': 'Replace',
    'code.closeFind': 'Close (Esc)',
    'code.nextMatch': 'Next match (Enter)',
    'code.prevMatch': 'Previous match (Shift+Enter)',
    'code.find': 'Find',
    'common.close': 'Close',
    'code.noProblems': 'No problems in this file.',
    'code.apply': 'Apply',
    'code.renameOthersTitle': 'Rename in other files?',
    'graph.import': 'Import',
    'common.cancel': 'Cancel',
    'graph.importHint':
        'path relative to the project, e.g. assets/ai/guard.json',
    'graph.importTitle': 'Import a behavior tree',
    'graph.selectNode': 'Select a node to edit it.',
    'graph.fit': 'Fit all nodes',
    'graph.zoomIn': 'Zoom in',
    'graph.zoomOut': 'Zoom out',
    'graph.importTooltip': 'Import a behavior tree JSON',
    'graph.export': 'Export engine JSON to assets/ai/',
    'graph.addNode': 'Add node',
    'graph.save': 'Save',
    'level.gameStarted': 'Game started. Its output is in .studio/playtest.log.',
    'level.title': 'Level',
    'level.stopGame': 'Stop the running game',
    'level.device': 'Run on',
    'level.runPreview': 'Run the level in the preview',
    'level.runGame': 'Run the game on this level (a separate process)',
    'level.save': 'Save (Cmd/Ctrl+S)',
    'level.showGrid': 'Show grid',
    'level.snapGrid': 'Snap to grid',
    'level.showTiles': 'Show tiles',
    'level.showEntities': 'Show entities',
    'level.deleteSelected': 'Delete selected entity',
    'level.takeOver': 'Take over',
    'level.modeEdit': 'Edit',
    'level.modePreview': 'Preview',
    'palette.search': 'Find a component',
    'palette.empty': 'Empty entity',
    'inspector.none': 'Select an entity to edit its properties.',
    'inspector.pickSprite': 'Pick sprite',
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
