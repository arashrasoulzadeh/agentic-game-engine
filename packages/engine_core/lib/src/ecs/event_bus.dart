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
  final Map<Type, List<Subscription>> _handlers = {};
  final Set<Type> _dirty = {};
  int _flushDepth = 0;
  final List<Object> _queue = [];

  /// Registers [handler] for events whose runtime type is exactly [T] (a
  /// handler for a base type does not receive subclass events).
  ///
  /// Returns a [Subscription]; call [Subscription.cancel] to stop delivery. A
  /// handler added while a flush is running first sees the *next* event
  /// dispatched, never the one being delivered.
  Subscription on<T>(void Function(T event) handler) {
    final sub = Subscription._(this, T, (event) => handler(event as T));
    (_handlers[T] ??= []).add(sub);
    return sub;
  }

  /// Like [on], but the handler is cancelled just before its first call, so it
  /// runs at most once even if it throws or emits the same event again.
  Subscription once<T>(void Function(T event) handler) {
    late final Subscription sub;
    sub = on<T>((event) {
      sub.cancel();
      handler(event);
    });
    return sub;
  }

  void _cancel(Subscription sub) {
    if (!sub._active) return;
    sub._active = false;
    if (_flushDepth > 0) {
      _dirty.add(sub._type);
    } else {
      _prune(sub._type);
    }
  }

  void _prune(Type type) {
    final list = _handlers[type];
    if (list == null) return;
    list.removeWhere((s) => !s._active);
    if (list.isEmpty) _handlers.remove(type);
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
    _flushDepth++;
    try {
      for (
        var round = 0;
        round < _maxCascadeRounds && _queue.isNotEmpty;
        round++
      ) {
        final pending = List<Object>.from(_queue);
        _queue.clear();
        for (final event in pending) {
          final handlers = _handlers[event.runtimeType];
          if (handlers == null) continue;
          final count = handlers.length;
          for (var i = 0; i < count; i++) {
            final sub = handlers[i];
            if (sub._active) sub._fn(event);
          }
        }
      }
    } finally {
      _flushDepth--;
      if (_flushDepth == 0 && _dirty.isNotEmpty) {
        for (final type in _dirty.toList()) {
          _prune(type);
        }
        _dirty.clear();
      }
    }
  }

  /// Cancels every handler of every type. Prefer cancelling the individual
  /// [Subscription]s you own; this exists for tearing a whole world down.
  void clearHandlers() {
    for (final list in _handlers.values) {
      for (final sub in list) {
        sub._active = false;
      }
    }
    _handlers.clear();
    _dirty.clear();
  }
}

/// A live registration on an [EventBus], returned by `on`/`once`.
class Subscription {
  final EventBus _bus;
  final Type _type;
  final void Function(Object) _fn;
  bool _active = true;

  Subscription._(this._bus, this._type, this._fn);

  /// Whether the handler can still be called.
  bool get isActive => _active;

  /// Stops delivery. Safe to call from inside a handler (including this
  /// one) and more than once; the handler is not called again, even for
  /// events already queued.
  void cancel() => _bus._cancel(this);
}
