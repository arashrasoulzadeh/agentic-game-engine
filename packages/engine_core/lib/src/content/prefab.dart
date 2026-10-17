import 'level_document.dart';

/// A reusable group of entities: a torch with its light, a door with its trigger, a
/// whole room. Stored relative to its own origin so it can be placed anywhere.
///
/// Plain data like a level (`prefabs/*.json`), so it is diffable, agent-writable and
/// loadable without code.
class Prefab {
  final String name;

  /// The entities, with every `position` stored relative to the group's origin.
  final List<LevelEntity> entities;

  Prefab({required this.name, required List<LevelEntity> entities}) : entities = List.of(entities);

  /// Captures [source] as a prefab. Positions are rewritten relative to the group's
  /// top-left corner (the smallest x and y of any positioned entity), so placing the
  /// prefab at (x, y) puts that corner at (x, y). Entities are deep-copied: later
  /// edits to the level don't change the prefab.
  factory Prefab.fromEntities(String name, List<LevelEntity> source) {
    double? minX, minY;
    for (final e in source) {
      final p = e.components['position'];
      if (p == null) continue;
      final x = (p['x'] as num).toDouble(), y = (p['y'] as num).toDouble();
      if (minX == null || x < minX) minX = x;
      if (minY == null || y < minY) minY = y;
    }
    final copies = [
      for (final e in source)
        _copy(e, dx: -(minX ?? 0), dy: -(minY ?? 0)),
    ];
    return Prefab(name: name, entities: copies);
  }

  /// New entities for placing this prefab with its origin at ([x], [y]): fresh
  /// copies (placing twice gives independent entities), positions offset, and names
  /// made unique against [taken] and each other (`torch` -> `torch2`) because entity
  /// names are how a game finds an entity.
  List<LevelEntity> instantiate(double x, double y, {Set<String> taken = const {}}) {
    final used = {...taken};
    final out = <LevelEntity>[];
    for (final template in entities) {
      final copy = _copy(template, dx: x, dy: y);
      final wanted = copy.name;
      if (wanted != null) {
        var name = wanted;
        var n = 2;
        while (!used.add(name)) {
          name = '$wanted${n++}';
        }
        copy.name = name;
      }
      out.add(copy);
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'entities': [for (final e in entities) e.toJson()],
      };

  factory Prefab.fromJson(Map<String, dynamic> json) => Prefab(
        name: json['name'] as String,
        entities: [
          for (final e in (json['entities'] as List? ?? const []))
            LevelEntity.fromJson((e as Map).cast<String, dynamic>()),
        ],
      );
}

LevelEntity _copy(LevelEntity e, {required double dx, required double dy}) {
  final components = {
    for (final entry in e.components.entries) entry.key: _deepCopy(entry.value) as Map<String, dynamic>,
  };
  final position = components['position'];
  if (position != null) {
    position['x'] = (position['x'] as num).toDouble() + dx;
    position['y'] = (position['y'] as num).toDouble() + dy;
  }
  return LevelEntity(name: e.name, components: components);
}

Object? _deepCopy(Object? v) {
  if (v is Map) return {for (final e in v.entries) e.key as String: _deepCopy(e.value)};
  if (v is List) return [for (final x in v) _deepCopy(x)];
  return v;
}
