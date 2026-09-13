import 'component_store.dart';
import 'entity.dart';

/// Thrown by [ComponentRegistry.applyToEntity] when a named component's
/// JSON is malformed — not shaped like a JSON object, or rejected by
/// that component's own `fromJson` (a wrong field type, a failed
/// constructor invariant like `TileMap`'s tiles-length check, etc.).
/// Carries [componentName]/[entity] so an agent/human debugging a bad
/// level file or `World.applyPatch` call gets "component 'health' on
/// entity 3 is broken", not a bare, contextless `TypeError` from deep
/// inside some component's `fromJson`.
class ComponentApplyException implements Exception {
  final String componentName;
  final EntityId entity;
  final Object cause;
  ComponentApplyException(this.componentName, this.entity, this.cause);

  @override
  String toString() =>
      'ComponentApplyException: component "$componentName" on entity '
      '$entity: $cause';
}

/// Bundles a `ComponentStore<T>` with its (de)serializers so World.toJson()
/// can dump arbitrary component types without hardcoding them — this is
/// what lets an agent read/write world state as plain JSON regardless of
/// which components a given game defines.
class ComponentRegistration<T> {
  final String name;
  final ComponentStore<T> store = ComponentStore<T>();
  final Map<String, dynamic> Function(T) toJson;
  final T Function(Map<String, dynamic>) fromJson;

  ComponentRegistration(this.name, this.toJson, this.fromJson);

  /// Type-erased entry points so ComponentRegistry can call these through
  /// a raw (unparameterized) reference without Dart rejecting the
  /// contravariant Function-typed field access.
  dynamic serialize(EntityId entity) {
    final value = store.get(entity);
    return value == null ? null : toJson(value);
  }

  void applyJson(EntityId entity, Map<String, dynamic> json) {
    store.set(entity, fromJson(json));
  }

  void removeEntity(EntityId entity) => store.remove(entity);
}

class ComponentRegistry {
  final Map<Type, ComponentRegistration> _byType = {};
  final Map<String, ComponentRegistration> _byName = {};

  void register<T>(
    String name,
    Map<String, dynamic> Function(T) toJson,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final reg = ComponentRegistration<T>(name, toJson, fromJson);
    _byType[T] = reg;
    _byName[name] = reg;
  }

  ComponentStore<T> storeOf<T>() {
    final reg = _byType[T];
    if (reg == null) {
      throw StateError(
          'Component type $T is not registered. Call registry.register<$T>() first.');
    }
    return reg.store as ComponentStore<T>;
  }

  /// Dumps every registered component attached to [entity] as {name: json}.
  Map<String, dynamic> serializeEntity(EntityId entity) {
    final out = <String, dynamic>{};
    for (final reg in _byType.values) {
      final json = reg.serialize(entity);
      if (json != null) {
        out[reg.name] = json;
      }
    }
    return out;
  }

  /// Applies {name: json} component data onto [entity], creating or
  /// overwriting each named component. Unknown names are skipped rather
  /// than throwing, so partial/forward-compatible patches from an agent
  /// don't hard-fail the whole apply.
  void applyToEntity(EntityId entity, Map<String, dynamic> components) {
    for (final entry in components.entries) {
      final reg = _byName[entry.key];
      if (reg == null) continue;
      final rawValue = entry.value;
      if (rawValue is! Map) {
        throw ComponentApplyException(
          entry.key,
          entity,
          'expected an object, got ${rawValue.runtimeType}',
        );
      }
      try {
        reg.applyJson(entity, rawValue.cast<String, dynamic>());
      } on ComponentApplyException {
        rethrow;
      } catch (cause) {
        throw ComponentApplyException(entry.key, entity, cause);
      }
    }
  }

  Iterable<ComponentRegistration> get all => _byType.values;
}
