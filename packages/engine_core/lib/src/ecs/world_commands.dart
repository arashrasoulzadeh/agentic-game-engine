import 'entity.dart';
import 'world.dart';

/// Changes to the world queued now and applied at a safe point.
///
/// Destroying or detaching components while iterating a component collection
/// reorders it (stores swap-remove), so a loop that destroys as it goes skips
/// entities. Systems queue those changes here instead; [World.step] applies
/// the queue after every system, and again after events are flushed, so the
/// next system always sees the result.
///
/// Each queued change remembers the entity's generation when it was queued
/// and is skipped if that entity is gone by the time it runs, including when
/// its id has been reused. Changes run in the order queued.
class WorldCommands {
  final World _world;
  List<void Function()> _queue = [];

  WorldCommands(this._world);

  /// Whether nothing is waiting to be applied.
  bool get isEmpty => _queue.isEmpty;

  /// How many changes are waiting.
  int get length => _queue.length;

  /// Creates an entity right away and returns its id, so later commands (and
  /// your own code) can refer to it. Creating is safe mid-iteration: it does
  /// not move any existing component. The entity has no components yet.
  EntityId spawn() => _world.spawn();

  /// Queues attaching [value] as [entity]'s [T].
  void set<T>(EntityId entity, T value) {
    final generation = _world.generationOf(entity);
    _queue.add(() {
      if (_world.entities.isCurrent(entity, generation)) {
        _world.setComponent(entity, value);
      }
    });
  }

  /// Queues detaching [entity]'s [T].
  void remove<T>(EntityId entity) {
    final generation = _world.generationOf(entity);
    _queue.add(() {
      if (_world.entities.isCurrent(entity, generation)) {
        _world.removeComponent<T>(entity);
      }
    });
  }

  /// Queues destroying [entity]. Queuing it twice is harmless.
  void destroy(EntityId entity) {
    final generation = _world.generationOf(entity);
    _queue.add(() {
      if (_world.entities.isCurrent(entity, generation)) {
        _world.destroy(entity);
      }
    });
  }

  /// Runs everything queued, in order, then empties the queue.
  ///
  /// If a change throws, the rest still run and the first error is rethrown
  /// afterwards, so one bad command cannot strand the others.
  void apply() {
    if (_queue.isEmpty) return;
    final pending = _queue;
    _queue = [];
    Object? firstError;
    StackTrace? firstStack;
    for (final run in pending) {
      try {
        run();
      } on Object catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}
