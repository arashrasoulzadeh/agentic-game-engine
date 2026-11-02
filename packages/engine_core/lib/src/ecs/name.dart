import 'entity.dart';
import 'world.dart';

/// A unique-by-convention label for one entity (`player`, `exit_door`), so
/// code can fetch it with [WorldNames.find] instead of carrying ids around.
///
/// Unlike [EntityTags] (many entities share a tag), a name identifies a single
/// entity. A real registered component, so it saves, loads and diffs like
/// everything else. Levels give every entity with a `name` key this component.
class Name {
  final String value;

  const Name(this.value);

  Map<String, dynamic> toJson() => {'value': value};

  factory Name.fromJson(Map<String, dynamic> json) =>
      Name(json['value'] as String);
}

/// Name access on [World].
extension WorldNames on World {
  /// Gives [entity] the [name], replacing any earlier one.
  ///
  /// Throws [StateError] if [entity] is not alive (see [World.setComponent]).
  /// Names are not forced unique; [find] returns the lowest-id match.
  void setName(EntityId entity, String name) =>
      setComponent(entity, Name(name));

  /// The name of [entity], or null if it has none.
  String? nameOf(EntityId entity) => getComponent<Name>(entity)?.value;

  /// The entity called [name], or null. If several share it, the one with the
  /// lowest id, so the answer is stable. A scan: look it up once and keep the
  /// id (with [World.generationOf] if it can be destroyed), not every frame.
  EntityId? find(String name) {
    final names = componentsOf<Name>();
    EntityId? best;
    for (var i = 0; i < names.length; i++) {
      if (names.denseAt(i).value != name) continue;
      final id = names.entityAt(i);
      if (best == null || id < best) best = id;
    }
    return best;
  }
}
