/// Upgrades old saves one version at a time, so each shape change is written
/// once and old saves keep loading however many versions behind they are.
///
/// ```dart
/// final migrations = SaveMigrations()
///   ..step(1, (w) => SaveMigrations.renameField(w, 'health', 'hp', 'current'))
///   ..step(2, (w) => SaveMigrations.renameComponent(w, 'hp', 'life'));
/// await SaveGame.load(world, version: 3, migrate: migrations.call);
/// ```
///
/// A step N takes world JSON at version N and returns it at version N + 1.
/// Steps may edit the map they are given; [call] hands each step a deep copy
/// so a failing migration never damages the caller's data.
class SaveMigrations {
  final Map<int, Map<String, dynamic> Function(Map<String, dynamic>)> _steps =
      {};

  /// Registers the step that upgrades version [from] to `from + 1`.
  void step(
    int from,
    Map<String, dynamic> Function(Map<String, dynamic> world) fn,
  ) {
    if (_steps.containsKey(from)) {
      throw ArgumentError('A migration from version $from is already set.');
    }
    _steps[from] = fn;
  }

  /// Upgrades [world] from [savedVersion] to [targetVersion]. Throws a
  /// [StateError] naming the missing step when the chain has a gap, or when
  /// the save is newer than the game.
  Map<String, dynamic> migrate(
    Map<String, dynamic> world,
    int savedVersion,
    int targetVersion,
  ) {
    if (savedVersion > targetVersion) {
      throw StateError(
        'Save is at version $savedVersion but the game is at '
        '$targetVersion; it was written by a newer build.',
      );
    }
    var json = _deepCopy(world) as Map<String, dynamic>;
    for (var v = savedVersion; v < targetVersion; v++) {
      final fn = _steps[v];
      if (fn == null) {
        throw StateError(
          'No save migration from version $v to ${v + 1} '
          '(needed to reach $targetVersion).',
        );
      }
      json = fn(json);
    }
    return json;
  }

  /// Shape of `SaveGame.load`'s `migrate:` callback; it needs the target
  /// version, so bind it: `migrate: (w, v) => migrations.migrate(w, v, 3)`.
  Map<String, dynamic> Function(Map<String, dynamic>, int) forVersion(
    int targetVersion,
  ) =>
      (world, saved) => migrate(world, saved, targetVersion);

  /// Renames component [from] to [to] on every entity that has it.
  static Map<String, dynamic> renameComponent(
    Map<String, dynamic> world,
    String from,
    String to,
  ) {
    for (final components in _componentMaps(world)) {
      if (components.containsKey(from)) {
        components[to] = components.remove(from);
      }
    }
    return world;
  }

  /// Renames [fromField] to [toField] inside every [component].
  static Map<String, dynamic> renameField(
    Map<String, dynamic> world,
    String component,
    String fromField,
    String toField,
  ) {
    for (final components in _componentMaps(world)) {
      final data = components[component];
      if (data is Map<String, dynamic> && data.containsKey(fromField)) {
        data[toField] = data.remove(fromField);
      }
    }
    return world;
  }

  /// Adds [field] = [value] to every [component] that lacks it.
  static Map<String, dynamic> addField(
    Map<String, dynamic> world,
    String component,
    String field,
    Object? value,
  ) {
    for (final components in _componentMaps(world)) {
      final data = components[component];
      if (data is Map<String, dynamic>) data.putIfAbsent(field, () => value);
    }
    return world;
  }

  static Iterable<Map<String, dynamic>> _componentMaps(
    Map<String, dynamic> world,
  ) sync* {
    final entities = world['entities'];
    if (entities is! List) return;
    for (final e in entities) {
      if (e is Map<String, dynamic> &&
          e['components'] is Map<String, dynamic>) {
        yield e['components'] as Map<String, dynamic>;
      }
    }
  }

  static Object? _deepCopy(Object? v) {
    if (v is Map) {
      return {for (final e in v.entries) e.key as String: _deepCopy(e.value)};
    }
    if (v is List) return [for (final e in v) _deepCopy(e)];
    return v;
  }
}
