import 'dart:convert';

import 'package:path/path.dart' as p;

import '../context.dart';
import 'studio_project.dart';

/// Merges [existing] with the project's name, engine pin and level list.
///
/// Unknown keys in [existing] are kept so hand-edited notes survive a rewrite.
Map<String, Object?> mergeProjectManifest({
  required String pubspecText,
  required List<String> levels,
  Map<String, Object?> existing = const {},
}) => {
  ...existing,
  'name': pubspecName(pubspecText),
  'engineVersion': engineCoreRef(pubspecText),
  'levels': List<String>.from(levels),
};

/// Builds a fresh `project.json` map for the open project in [ctx].
Map<String, Object?> projectManifestFor(OpContext ctx) {
  final root = ctx.project!.root;
  final existingText = ctx.files.read(p.join(root, 'project.json'));
  final existing = existingText == null
      ? <String, Object?>{}
      : (jsonDecode(existingText) as Map).cast<String, Object?>();
  final pubspec = ctx.files.read(p.join(root, 'pubspec.yaml')) ?? '';
  return mergeProjectManifest(
    pubspecText: pubspec,
    levels: StudioProject.open(root).levelPaths(),
    existing: existing,
  );
}

/// The `name:` field from a pubspec, or `unnamed`.
String pubspecName(String pubspec) {
  final m = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(pubspec);
  return m?.group(1)?.trim().replaceAll(RegExp(r'''['"]'''), '') ?? 'unnamed';
}

/// The `engine_core` git `ref` pinned in [pubspec], or `unknown`.
String engineCoreRef(String pubspec) {
  final m = RegExp(
    r'^\s{2}engine_core:\s*$[\s\S]*?^\s{6}ref:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec);
  return m?.group(1)?.replaceAll(RegExp(r'''['"]'''), '') ?? 'unknown';
}

/// Canonical JSON for `project.json` (two-space indent + trailing newline).
String encodeProjectManifest(Map<String, Object?> manifest) =>
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n';
