import '../physics/position.dart';
import 'entity.dart';
import 'entity_handle.dart';
import 'world.dart';

/// Creating an entity with its components in one expression.
extension EntitySpawning on World {
  /// Spawns an entity and attaches every value in [components], matching each
  /// to its registered type by `runtimeType`.
  ///
  /// All-or-nothing: an unregistered type or a type listed twice throws
  /// before anything is spawned, so a mistake never leaves a half-built
  /// entity behind. Because the match is on the exact runtime type, a
  /// subclass instance is rejected unless the subclass itself is registered.
  ///
  /// ```dart
  /// final id = world.spawnWith([Position(10, 20), Velocity(5, 0)]);
  /// ```
  EntityId spawnWith(Iterable<Object> components) {
    final values = components.toList();
    final seen = <Type>{};
    for (final value in values) {
      final type = value.runtimeType;
      if (this.components.getRegistration(type) == null) {
        throw ArgumentError.value(
          value,
          'components',
          'Component type $type is not registered. Register it first '
              '(registerCoreComponents & co. or components.register<$type>()).',
        );
      }
      if (!seen.add(type)) {
        throw ArgumentError.value(
          value,
          'components',
          'Component type $type appears more than once for one entity.',
        );
      }
    }
    final id = spawn();
    for (final value in values) {
      this.components.getRegistration(value.runtimeType)!.store.set(id, value);
    }
    return id;
  }

  /// Spawns an entity with a [Position] at ([x], [y]).
  EntityId spawnAt(double x, double y) => spawnWith([Position(x, y)]);

  /// Starts a fluent description of a new entity; nothing exists until
  /// [EntityBuilder.build].
  ///
  /// ```dart
  /// final player = world.entity().at(10, 20).add(Velocity(5, 0)).build();
  /// ```
  EntityBuilder entity() => EntityBuilder._(this);
}

/// Collects components for one new entity; see [EntitySpawning.entity].
class EntityBuilder {
  final World _world;
  final List<Object> _components = [];

  EntityBuilder._(this._world);

  /// Adds a [Position] at ([x], [y]).
  EntityBuilder at(double x, double y) => add(Position(x, y));

  /// Adds [component]. (`with` is a Dart keyword, hence `add`.)
  EntityBuilder add(Object component) {
    _components.add(component);
    return this;
  }

  /// Spawns the entity with everything collected and returns a live reference
  /// to it. Throws like [EntitySpawning.spawnWith] for bad components.
  EntityRef build() {
    final id = _world.spawnWith(_components);
    return _world.ref(_world.entityOf(id));
  }
}
