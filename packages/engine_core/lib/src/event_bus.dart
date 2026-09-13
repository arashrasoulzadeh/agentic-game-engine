/// Typed pub/sub so systems communicate without calling each other
/// directly — e.g. CollisionSystem emits CollisionEvent, a separate
/// DamageSystem subscribes to it. Keeps systems independently
/// understandable and safe for an agent to add/remove one at a time.
class EventBus {
  // Each handler is wrapped once at registration time (the `as T` cast
  // happens here, not per dispatch) into a plain `void Function(Object)`
  // -- a direct, inlinable call site. The previous version stored raw
  // `Function` objects and dispatched via `Function.apply`, which goes
  // through a slower dynamic-invocation path Dart can't optimize the
  // way a normal call is.
  final Map<Type, List<void Function(Object)>> _handlers = {};
  final List<Object> _queue = [];

  void on<T>(void Function(T event) handler) {
    (_handlers[T] ??= []).add((event) => handler(event as T));
  }

  void emit(Object event) => _queue.add(event);

  /// Cap on cascading rounds within one `flush()` call (see below) — a
  /// safety net against a genuine handler cycle (A's handler emits B,
  /// B's handler emits A, forever), not a limit any normal chain of
  /// reactions should ever approach.
  static const _maxCascadeRounds = 20;

  /// Dispatches all events queued since the last flush, including
  /// events emitted *by* a handler run during this same call — e.g. a
  /// `CollisionEvent` handler that emits a more specific event derived
  /// from it (`installTriggerZones` translating a touch into a
  /// `TriggerEvent`) delivers that new event within this same `flush()`,
  /// not one tick later. Without this, "something reacted to what this
  /// tick's collision produced" would be delayed a full tick from the
  /// collision itself — a real, surprising lag for anything chaining
  /// off another event rather than off a `System` directly. Call once
  /// per tick, after systems have had a chance to emit.
  void flush() {
    for (var round = 0; round < _maxCascadeRounds && _queue.isNotEmpty; round++) {
      final pending = List<Object>.from(_queue);
      _queue.clear();
      for (final event in pending) {
        final handlers = _handlers[event.runtimeType];
        if (handlers == null) continue;
        for (final h in handlers) {
          h(event);
        }
      }
    }
  }

  void clearHandlers() => _handlers.clear();
}
