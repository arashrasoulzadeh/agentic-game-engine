import 'level.dart';

/// One entity in a [LevelDocument]: an optional name (how other code finds
/// it, see [Level.loadInto]) and its components as plain JSON, keyed by
/// registered component name.
///
/// Components stay as JSON rather than typed objects. The studio edits the
/// same data the runtime loads, and keeping the JSON as written is what lets
/// a load-then-save cycle leave unchanged data byte-identical (STUDIO_TODO.md
/// 0.6).
class LevelEntity {
  String? name;
  final Map<String, Map<String, dynamic>> components;

  LevelEntity({this.name, Map<String, Map<String, dynamic>>? components})
    : components = components ?? {};

  /// Parses one already-validated entity. Callers should go through
  /// [LevelDocument.fromJson], which runs [Level.validate] first.
  factory LevelEntity.fromJson(Map<String, dynamic> json) {
    final rawComponents = json['components'] as Map? ?? const {};
    return LevelEntity(
      name: json['name'] as String?,
      components: {
        for (final entry in rawComponents.entries)
          entry.key as String: (entry.value as Map).cast<String, dynamic>(),
      },
    );
  }

  /// Emits `name` only when set, so an unnamed entity serializes the way it
  /// was written.
  Map<String, dynamic> toJson() => {
    if (name != null) 'name': name,
    'components': components,
  };
}

/// An editable, plain-data level: the document the studio's level editor
/// holds and saves. It is not a live `World`; loading it into one is
/// [Level.loadInto]'s job.
///
/// `fromJson` runs the same validation the runtime loader does, so a
/// document that loads in the engine also opens in the studio, and a
/// structurally bad file is rejected with the same [LevelLoadException].
class LevelDocument {
  final List<LevelEntity> entities;

  LevelDocument({List<LevelEntity>? entities}) : entities = entities ?? [];

  /// Validates [json] (throwing [LevelLoadException] on a structural
  /// problem), then parses every entity.
  factory LevelDocument.fromJson(Map<String, dynamic> json) => LevelDocument(
    entities: [
      for (final entityJson in Level.validate(json))
        LevelEntity.fromJson(entityJson),
    ],
  );

  /// The first entity carrying [name], or null. Names are not required to be
  /// unique on disk, so this returns the first match in file order, the same
  /// rule [Level.loadInto] uses when it builds its name-to-id map.
  LevelEntity? entityNamed(String name) {
    for (final entity in entities) {
      if (entity.name == name) return entity;
    }
    return null;
  }

  /// The level's JSON in the shape [Level.loadInto] reads.
  Map<String, dynamic> toJson() => {
    'entities': [for (final entity in entities) entity.toJson()],
  };
}
