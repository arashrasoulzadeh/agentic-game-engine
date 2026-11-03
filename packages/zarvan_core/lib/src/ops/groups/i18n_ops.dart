import 'dart:convert';

import 'package:path/path.dart' as p;

import '../../content/level_format.dart';
import '../context.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';

/// Project-relative folder for per-locale string catalogs.
const i18nDir = 'assets/i18n';

final _localeFile = RegExp(r'^[A-Za-z]{2}([_-][A-Za-z0-9]+)?\.json$');
final _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

String _localePath(String locale) => '$i18nDir/$locale.json';

/// Flat `{key: text}` map from a locale JSON file, or empty when missing.
Map<String, String> loadLocaleCatalog(OpContext ctx, String locale) {
  final text = ctx.files.read(ctx.project!.resolve(_localePath(locale)));
  if (text == null) return {};
  try {
    final json = jsonDecode(text);
    if (json is! Map) {
      throw OpError(
        ErrorCode.validationFailed,
        '$_localePath($locale) must be a JSON object of string keys to string values.',
      );
    }
    final out = <String, String>{};
    for (final e in json.entries) {
      if (e.value is! String) {
        throw OpError(
          ErrorCode.validationFailed,
          '$_localePath($locale): key "${e.key}" must be a string.',
        );
      }
      out['${e.key}'] = e.value as String;
    }
    return out;
  } on OpError {
    rethrow;
  } on Object catch (e) {
    throw OpError(
      ErrorCode.validationFailed,
      '$_localePath($locale) is not valid JSON ($e).',
    );
  }
}

/// Locales present as `assets/i18n/<locale>.json` (filename stems, e.g. `en`, `pt_BR`).
List<String> listLocales(OpContext ctx) {
  final abs = ctx.project!.resolve(i18nDir);
  return [
    for (final f in ctx.files.list(abs))
      if (_localeFile.hasMatch(p.basename(f))) p.basenameWithoutExtension(f),
  ]..sort();
}

Set<String> _placeholders(String text) => {
  for (final m in _placeholder.allMatches(text)) m.group(1)!,
};

/// `i18n.*`: game string catalogs under [i18nDir] (`<locale>.json` → flat key/text maps).
List<Operation> i18nOperations() => [
  Operation(
    name: 'i18n.keys',
    summary:
        'Report every i18n key, which locales have it, and placeholder mismatches.',
    description:
        'Reads `assets/i18n/<locale>.json` files (flat `{ "key": "text" }` maps — the same '
        'shape the studio uses for its own catalogs). Without `locale`, compares every file; '
        'with `locale`, that file is checked against the union of keys from all locales. '
        '`missing` lists keys absent from a locale; `placeholderMismatches` lists keys whose '
        '`{name}` placeholders differ across locales. `ok` is true when both are empty.',
    kind: OperationKind.read,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param(
        'locale',
        ParamType.string,
        description: 'Focus the missing report on this locale (e.g. fa).',
      ),
    ],
    handler: (ctx, a) {
      final locales = listLocales(ctx);
      if (locales.isEmpty) {
        return OpOutcome.data({
          'ok': true,
          'locales': <String>[],
          'keys': <String>[],
          'missing': <String, List<String>>{},
          'placeholderMismatches': <Map<String, Object?>>[],
          'hint':
              'No catalogs yet. Create assets/i18n/<locale>.json (flat key → text).',
        });
      }
      final catalogs = {
        for (final loc in locales) loc: loadLocaleCatalog(ctx, loc),
      };
      final allKeys = <String>{
        for (final c in catalogs.values) ...c.keys,
      }.toList()..sort();

      final focus = a['locale'] as String?;
      if (focus != null && !catalogs.containsKey(focus)) {
        throw OpError(
          ErrorCode.notFound,
          'No catalog for locale "$focus".',
          hint: 'Expected ${_localePath(focus)}. Known: ${locales.join(', ')}.',
        );
      }

      final missing = <String, List<String>>{};
      final checkLocales = focus == null ? locales : [focus];
      for (final loc in checkLocales) {
        final absent = [
          for (final k in allKeys)
            if (!catalogs[loc]!.containsKey(k)) k,
        ];
        if (absent.isNotEmpty) missing[loc] = absent;
      }

      final mismatches = <Map<String, Object?>>[];
      for (final key in allKeys) {
        final byLocale = <String, List<String>>{};
        for (final loc in locales) {
          final text = catalogs[loc]![key];
          if (text == null) continue;
          byLocale[loc] = (_placeholders(text).toList()..sort());
        }
        if (byLocale.length < 2) continue;
        final first = byLocale.values.first;
        if (byLocale.values.any(
          (p) => p.length != first.length || !_sameSet(p, first),
        )) {
          mismatches.add({'key': key, 'placeholders': byLocale});
        }
      }

      return OpOutcome.data({
        'ok': missing.isEmpty && mismatches.isEmpty,
        'locales': locales,
        'keys': allKeys,
        'keyCount': allKeys.length,
        'missing': missing,
        'placeholderMismatches': mismatches,
      });
    },
  ),
  Operation(
    name: 'i18n.set',
    summary: 'Set one key\'s text in a locale catalog.',
    description:
        'Writes `assets/i18n/<locale>.json` (creates the file when missing). Keys are '
        'sorted on write so diffs stay stable. Undoable via `undo.undo`.',
    kind: OperationKind.write,
    scope: OperationScope.project,
    idempotent: true,
    params: const [
      Param('locale', ParamType.string, required: true, positional: true),
      Param('key', ParamType.string, required: true),
      Param('text', ParamType.string, required: true),
    ],
    handler: (ctx, a) {
      final locale = a['locale']! as String;
      final key = a['key']! as String;
      final text = a['text']! as String;
      if (locale.isEmpty || locale.contains('/') || locale.contains('\\')) {
        throw OpError(
          ErrorCode.invalidParams,
          'locale must be a simple code such as "en" or "pt_BR".',
        );
      }
      if (key.isEmpty) {
        throw OpError(ErrorCode.invalidParams, 'key must not be empty.');
      }
      final rel = _localePath(locale);
      final before = ctx.files.read(ctx.project!.resolve(rel));
      final catalog = Map<String, String>.from(loadLocaleCatalog(ctx, locale));
      final previous = catalog[key];
      catalog[key] = text;
      final sorted = Map.fromEntries(
        catalog.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      );
      final after = encodeLevelJson(sorted);
      return OpOutcome.proposal(
        Proposal([FileChange(path: rel, before: before, after: after)]),
        data: {
          'locale': locale,
          'key': key,
          'before': previous,
          'after': text,
          'path': rel,
          'created': before == null,
        },
      );
    },
  ),
];

bool _sameSet(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
