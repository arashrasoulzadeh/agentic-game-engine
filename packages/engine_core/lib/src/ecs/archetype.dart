import 'entity.dart';
import 'component_registry.dart';

/// A unique combination of component types — an "archetype" in ECS terms.
/// Entities with the exact same set of components belong to the same archetype.
/// Systems can iterate over a single archetype's dense component arrays without
/// cross-component lookups, which is much faster than sparse-set iteration with
/// `has()` checks.
class Archetype {
  final List<dynamic> _stores;

  /// The component types in this archetype (same order as _stores).
  final List<Type> componentTypes;

  Archetype._(this._stores, this.componentTypes);

  /// Creates an archetype from the given component stores.
  factory Archetype.create(List<dynamic> stores, List<Type> types) {
    return Archetype._(stores, types);
  }

  /// Number of entities in this archetype.
  int get length => _stores.isEmpty ? 0 : _stores.first.length;

  /// Returns the dense array for component type T, or null if not in this archetype.
  List<T>? dense<T>() {
    final idx = componentTypes.indexOf(T);
    if (idx == -1) return null;
    return _stores[idx]._denseArray.cast<T>();
  }

  /// Returns the entity at index i.
  EntityId entityAt(int i) => _stores.first._denseEntities[i];

  /// Checks if this archetype has the given component type.
  bool hasComponent<T>() => componentTypes.contains(T);

  /// Iterates all entities in this archetype, providing access to components.
  Iterable<ArchetypeEntity> iterate() sync* {
    for (var i = 0; i < length; i++) {
      yield ArchetypeEntity._(this, i);
    }
  }
}

/// Provides access to a single entity's components within an archetype.
class ArchetypeEntity {
  final Archetype _archetype;
  final int _index;

  ArchetypeEntity._(this._archetype, this._index);

  EntityId get entityId => _archetype.entityAt(_index);

  /// Gets the component of type T for this entity.
  T? get<T>() {
    final idx = _archetype.componentTypes.indexOf(T);
    if (idx == -1) return null;
    return _archetype._stores[idx]._denseArray[_index] as T?;
  }

  /// Gets the component of type T, asserting it exists.
  T require<T>() {
    final value = get<T>();
    if (value == null) {
      throw StateError('Entity $entityId does not have component $T');
    }
    return value;
  }
}

/// Manages archetype membership for all entities in a World.
/// When components are added/removed, entities move between archetypes.
class ArchetypeManager {
  final Map<int, Archetype> _archetypes = {};
  final Map<EntityId, int> _entityArchetype = {};
  final ComponentRegistry _registry;

  ArchetypeManager(this._registry);

  /// Computes a stable hash for a set of component types.
  int _hashTypes(Iterable<Type> types) {
    final sorted = types.toList()..sort((a, b) => a.hashCode.compareTo(b.hashCode));
    var hash = 0;
    for (final t in sorted) {
      hash = (hash * 31) + t.hashCode;
    }
    return hash;
  }

  /// Gets or creates the archetype for the given component types.
  Archetype _getOrCreateArchetype(Set<Type> types) {
    final hash = _hashTypes(types);
    final existing = _archetypes[hash];
    if (existing != null) return existing;

    // Create new archetype with stores for each component type
    final stores = <dynamic>[];
    for (final type in types) {
      final reg = _registry.getRegistration(type);
      if (reg != null) {
        stores.add(reg.store);
      }
    }
    final archetype = Archetype.create(stores, types.toList());
    _archetypes[hash] = archetype;
    return archetype;
  }

  /// Updates an entity's archetype membership based on its current components.
  void refreshEntity(EntityId entity) {
    final currentComponents = _getEntityComponents(entity);
    final hash = _hashTypes(currentComponents);
    final currentArchetypeId = _entityArchetype[entity];

    if (currentArchetypeId == hash) return; // No change

    // Add to new archetype
    _entityArchetype[entity] = hash;
    _getOrCreateArchetype(currentComponents);
  }

  /// Gets the component types an entity currently has.
  Set<Type> _getEntityComponents(EntityId entity) {
    final types = <Type>{};
    for (final reg in _registry.all) {
      if (reg.store.has(entity)) {
        types.add(reg.type);
      }
    }
    return types;
  }

  /// Gets the archetype for an entity, or null if entity has no components.
  Archetype? getArchetype(EntityId entity) {
    final id = _entityArchetype[entity];
    return id != null ? _archetypes[id] : null;
  }

  /// Returns all archetypes that contain ALL of the given component types.
  Iterable<Archetype> archetypesWithAll(Iterable<Type> types) {
    final required = types.toSet();
    return _archetypes.values.where((a) => required.every((t) => a.componentTypes.contains(t)));
  }

  /// Called when an entity is destroyed — cleans up tracking.
  void onEntityDestroyed(EntityId entity) {
    _entityArchetype.remove(entity);
  }

  /// Called when a component is added to an entity.
  void onComponentAdded(EntityId entity, Type type) {
    refreshEntity(entity);
  }

  /// Called when a component is removed from an entity.
  void onComponentRemoved(EntityId entity, Type type) {
    refreshEntity(entity);
  }
}