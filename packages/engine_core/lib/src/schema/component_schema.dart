/// The JSON-level type of one component field, as the studio's inspector
/// and `game_agent studio validate` need to see it. Deliberately coarse:
/// these map to the widgets/validators a field needs, not to Dart's type
/// system (a `double` and an `int` field both edit as a number, but the
/// validator still rejects `1.5` for an `int`).
enum FieldType { int, double, bool, string, enumeration, vector2, list, object }

/// One field of a component: its JSON key, its [FieldType], an optional
/// numeric range, and the default a new entity starts with.
///
/// Schemas are explicit lists written next to each component, not
/// reflection over its fields — see STUDIO_TODO.md decision D1. That
/// keeps the field list reviewable and lets a test assert it matches the
/// component's `toJson` keys.
class FieldSchema {
  final String name;
  final FieldType type;
  final num? min;
  final num? max;
  final List<String> options;
  final Object? defaultValue;

  /// True for fields a component only serializes when set (`if (x != null)`
  /// in its `toJson`), or that serialize as `null` when unset. A missing or
  /// null optional value is valid; any other value is still checked against
  /// [type].
  final bool optional;

  const FieldSchema(
    this.name,
    this.type, {
    this.min,
    this.max,
    this.options = const [],
    this.defaultValue,
    this.optional = false,
  });

  /// Returns null when [value] is valid for this field, otherwise a
  /// message naming the field and why it was rejected. The message is
  /// shown verbatim in the studio's validation panel, so it names the
  /// field rather than just saying "invalid".
  String? validate(Object? value) {
    if (value == null && optional) return null;
    switch (type) {
      case FieldType.int:
        if (value is! int) return '$name must be an integer';
        return _checkRange(value);
      case FieldType.double:
        if (value is! num) return '$name must be a number';
        return _checkRange(value);
      case FieldType.bool:
        return value is bool ? null : '$name must be true or false';
      case FieldType.string:
        return value is String ? null : '$name must be a string';
      case FieldType.enumeration:
        if (value is! String || !options.contains(value)) {
          return '$name must be one of ${options.join(', ')}';
        }
        return null;
      case FieldType.list:
        return value is List ? null : '$name must be a list';
      case FieldType.object:
        return value is Map ? null : '$name must be an object';
      case FieldType.vector2:
        final ok =
            value is List &&
            value.length == 2 &&
            value.every((component) => component is num);
        return ok ? null : '$name must be a [x, y] pair of numbers';
    }
  }

  String? _checkRange(num value) {
    if (min != null && value < min!) return '$name must be at least $min';
    if (max != null && value > max!) return '$name must be at most $max';
    return null;
  }
}

/// The full field list of one registered component type, keyed by the
/// same name the component is registered under in
/// `World.components` — so the studio can go from a registered name to
/// its inspector layout without knowing the Dart type.
class ComponentSchema {
  final String name;
  final List<FieldSchema> fields;

  const ComponentSchema(this.name, this.fields);

  /// The JSON keys this schema declares, in declaration order. Used to
  /// check the schema against a component's real `toJson` output.
  List<String> get fieldNames => [for (final field in fields) field.name];

  /// A JSON object holding every field's [FieldSchema.defaultValue], for a
  /// new entity's component. Fields without a default are omitted, so
  /// `fromJson` can reject them loudly rather than inventing a value.
  Map<String, Object?> get defaults => {
    for (final field in fields)
      if (field.defaultValue != null) field.name: field.defaultValue,
  };

  /// Every field error in [json], empty when the object is valid. Returns
  /// all of them rather than the first so the inspector can show the
  /// full list at once.
  List<String> validate(Map<String, Object?> json) {
    final errors = <String>[];
    for (final field in fields) {
      if (!json.containsKey(field.name)) {
        if (!field.optional) errors.add('${field.name} is missing');
        continue;
      }
      final error = field.validate(json[field.name]);
      if (error != null) errors.add(error);
    }
    return errors;
  }
}
