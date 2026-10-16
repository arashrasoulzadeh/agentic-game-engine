import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Per-project code editor preferences (STUDIO_TODO.md IDE.13): font size,
/// indent width, and whether saving runs the formatter first. Stored under
/// `.studio/`, the same place autosave backups live — never the project's
/// own files.
class EditorSettings {
  final double fontSize;
  final int tabWidth;
  final bool formatOnSave;

  const EditorSettings({
    this.fontSize = 13,
    this.tabWidth = 2,
    this.formatOnSave = false,
  });

  EditorSettings copyWith({
    double? fontSize,
    int? tabWidth,
    bool? formatOnSave,
  }) => EditorSettings(
    fontSize: fontSize ?? this.fontSize,
    tabWidth: tabWidth ?? this.tabWidth,
    formatOnSave: formatOnSave ?? this.formatOnSave,
  );

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'tabWidth': tabWidth,
    'formatOnSave': formatOnSave,
  };

  /// Parses [json], falling back to each field's default for anything
  /// missing or the wrong type, so a hand-edited or partially-written
  /// settings file degrades gracefully instead of failing to load at all.
  factory EditorSettings.fromJson(Map<String, dynamic> json) {
    const fallback = EditorSettings();
    final fontSize = json['fontSize'];
    final tabWidth = json['tabWidth'];
    final formatOnSave = json['formatOnSave'];
    return EditorSettings(
      fontSize: fontSize is num ? fontSize.toDouble() : fallback.fontSize,
      tabWidth: tabWidth is int ? tabWidth : fallback.tabWidth,
      formatOnSave: formatOnSave is bool
          ? formatOnSave
          : fallback.formatOnSave,
    );
  }
}

/// Reads and writes a project's [EditorSettings] at
/// `<projectRoot>/.studio/editor_settings.json`.
class EditorSettingsStore {
  final String projectRoot;

  const EditorSettingsStore(this.projectRoot);

  String get _path => p.join(projectRoot, '.studio', 'editor_settings.json');

  /// The saved settings, or the defaults when nothing has been saved yet or
  /// the file can't be read as valid settings JSON.
  EditorSettings read() {
    final file = File(_path);
    if (!file.existsSync()) return const EditorSettings();
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map<String, dynamic>) return const EditorSettings();
      return EditorSettings.fromJson(json);
    } on Object {
      return const EditorSettings();
    }
  }

  void write(EditorSettings settings) {
    final file = File(_path)..createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }
}
