import 'entity.dart';
import 'world.dart';

/// Free-form string labels on an entity (`enemy`, `pickup`, `boss`), for
/// marking and finding groups without defining a component class per label.
///
/// (Named `EntityTags`, not `Tags`: `package:test` exports a `Tags`, which
/// would make every test that imports both ambiguous.)
///
/// A real registered component, so tags save, load, diff and appear in the
/// studio like everything else. Prefer a dedicated component when the label
/// carries data or a system needs a fast typed query; use tags for cheap
/// grouping and for content authored as JSON.
class EntityTags {
  /// The labels. Unordered; JSON lists them sorted so output is stable.
  final Set<String> values;

  EntityTags([Iterable<String> values = const []]) : values = {...values};

  Map<String, dynamic> toJson() => {'tags': (values.toList()..sort())};

  factory EntityTags.fromJson(Map<String, dynamic> json) =>
      EntityTags(((json['tags'] as List?) ?? const []).cast<String>());
}

/// Tag access on [World].
extension WorldTags on World {
  /// Adds [tag] to [entity], creating its [EntityTags] if needed.
  ///
  /// Throws [StateError] if [entity] is not alive (see [World.setComponent]).
  void addTag(EntityId entity, String tag) {
    final tags = getComponent<EntityTags>(entity);
    if (tags != null) {
      tags.values.add(tag);
    } else {
      setComponent(entity, EntityTags([tag]));
    }
  }

  /// Removes [tag] from [entity]; drops the [EntityTags] component once it is empty
  /// so serialized worlds carry no empty tag lists. A no-op if absent.
  void removeTag(EntityId entity, String tag) {
    final tags = getComponent<EntityTags>(entity);
    if (tags == null) return;
    tags.values.remove(tag);
    if (tags.values.isEmpty) removeComponent<EntityTags>(entity);
  }

  /// Whether [entity] carries [tag].
  bool hasTag(EntityId entity, String tag) =>
      getComponent<EntityTags>(entity)?.values.contains(tag) ?? false;

  /// Every entity carrying [tag], in storage order.
  Iterable<EntityId> withTag(String tag) sync* {
    final store = componentsOf<EntityTags>();
    for (var i = 0; i < store.length; i++) {
      if (store.denseAt(i).values.contains(tag)) yield store.entityAt(i);
    }
  }
}
