import 'result.dart';

enum ParamType {
  string,
  integer,
  number,
  boolean,
  enumeration,
  array,
  object,
  json,
  path,
}

/// One typed, documented parameter of an operation.
///
/// `path` values are project-relative strings (sandboxed by `ProjectRoot.resolve`); `json` is any JSON value.
class Param {
  const Param(
    this.name,
    this.type, {
    this.required = false,
    this.defaultValue,
    this.description = '',
    this.min,
    this.max,
    this.options = const [],
    this.items,
    this.properties = const [],
    this.positional = false,
    this.cliFlag,
    this.cliAbbr,
    this.secret = false,
  });

  /// An anonymous string, for `items:`.
  const Param.string() : this('', ParamType.string);

  final String name;
  final ParamType type;
  final bool required;
  final Object? defaultValue;
  final String description;
  final num? min;
  final num? max;
  final List<String> options;

  /// Element type of an `array`.
  final Param? items;

  /// Known keys of an `object` (others are allowed and passed through).
  final List<Param> properties;

  /// CLI only: given as a positional argument, in declaration order.
  final bool positional;
  final String? cliFlag;
  final String? cliAbbr;

  /// Never echoed in help, docs examples or request logs.
  final bool secret;
}

/// Checks and coerces raw arguments against a parameter list: strings from the CLI become numbers and booleans,
/// defaults fill in, unknown keys are refused (so a typo never silently does nothing), and every problem is
/// reported at once.
class ParamValidator {
  ParamValidator(this.params, {this.implicit = const []});

  final List<Param> params;

  /// Parameters the registry adds to every write operation (`apply`, `confirmation`).
  final List<Param> implicit;

  List<Param> get _all => [...params, ...implicit];

  Map<String, Object?> coerce(Map<String, Object?> raw) {
    final problems = <String>[];
    final byName = {for (final p in _all) p.name: p};
    for (final key in raw.keys) {
      if (!byName.containsKey(key)) {
        problems.add(
          'unknown parameter "$key" (allowed: ${byName.keys.join(', ')})',
        );
      }
    }
    final out = <String, Object?>{};
    for (final p in _all) {
      final has = raw.containsKey(p.name) && raw[p.name] != null;
      if (!has) {
        if (p.required) {
          problems.add('"${p.name}" is required');
        } else if (p.defaultValue != null) {
          out[p.name] = p.defaultValue;
        }
        continue;
      }
      final v = _value(p, raw[p.name], p.name, problems);
      if (v != _bad) out[p.name] = v;
    }
    if (problems.isNotEmpty) {
      throw OpError(
        ErrorCode.invalidParams,
        problems.length == 1
            ? problems.first
            : '${problems.length} problems with the parameters.',
        details: {'problems': problems},
      );
    }
    return out;
  }

  static const _bad = _Bad();

  Object? _value(Param p, Object? v, String path, List<String> problems) {
    switch (p.type) {
      case ParamType.string:
      case ParamType.path:
        if (v is! String) {
          problems.add('"$path" must be a string');
          return _bad;
        }
        if (p.type == ParamType.path && v.isEmpty) {
          problems.add('"$path" must not be empty');
          return _bad;
        }
        return v;
      case ParamType.integer:
        final n = v is int
            ? v
            : v is double && v == v.truncateToDouble()
            ? v.toInt()
            : v is String
            ? int.tryParse(v.trim())
            : null;
        if (n == null) {
          problems.add('"$path" must be an integer');
          return _bad;
        }
        return _range(p, n, path, problems) ? n : _bad;
      case ParamType.number:
        final n = v is num
            ? v
            : v is String
            ? num.tryParse(v.trim())
            : null;
        if (n == null) {
          problems.add('"$path" must be a number');
          return _bad;
        }
        return _range(p, n, path, problems) ? n : _bad;
      case ParamType.boolean:
        if (v is bool) return v;
        if (v == 'true') return true;
        if (v == 'false') return false;
        problems.add('"$path" must be true or false');
        return _bad;
      case ParamType.enumeration:
        if (v is String && p.options.contains(v)) return v;
        problems.add('"$path" must be one of: ${p.options.join(', ')}');
        return _bad;
      case ParamType.array:
        if (v is! List) {
          problems.add('"$path" must be a list');
          return _bad;
        }
        final item = p.items;
        if (item == null) return List<Object?>.of(v);
        final out = <Object?>[];
        for (var i = 0; i < v.length; i++) {
          final e = _value(item, v[i], '$path[$i]', problems);
          if (e != _bad) out.add(e);
        }
        return out;
      case ParamType.object:
        if (v is! Map) {
          problems.add('"$path" must be an object');
          return _bad;
        }
        return v.cast<String, Object?>();
      case ParamType.json:
        return v;
    }
  }

  bool _range(Param p, num n, String path, List<String> problems) {
    if (p.min != null && n < p.min!) {
      problems.add('"$path" must be at least ${p.min}');
      return false;
    }
    if (p.max != null && n > p.max!) {
      problems.add('"$path" must be at most ${p.max}');
      return false;
    }
    return true;
  }
}

class _Bad {
  const _Bad();
}
