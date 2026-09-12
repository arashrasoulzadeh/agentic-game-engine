/// Typed pub/sub so systems communicate without calling each other
/// directly — e.g. CollisionSystem emits CollisionEvent, a separate
/// DamageSystem subscribes to it. Keeps systems independently
/// understandable and safe for an agent to add/remove one at a time.
class EventBus {
  final Map<Type, List<Function>> _handlers = {};
  final List<Object> _queue = [];

  void on<T>(void Function(T event) handler) {
    (_handlers[T] ??= []).add(handler);
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
        Function.apply(h, [event]);
      }
    }
  }

  void clearHandlers() => _handlers.clear();
}
