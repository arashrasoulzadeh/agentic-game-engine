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

  /// Dispatches all events queued since the last flush. Call once per
  /// tick, after systems have had a chance to emit.
  void flush() {
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

  void clearHandlers() => _handlers.clear();
}
