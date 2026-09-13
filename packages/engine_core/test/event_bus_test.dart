import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _EventA {
  const _EventA();
}

class _EventB {
  const _EventB();
}

void main() {
  test('flush delivers a plain event to its handler', () {
    final bus = EventBus();
    var received = false;
    bus.on<_EventA>((_) => received = true);

    bus.emit(const _EventA());
    bus.flush();

    expect(received, isTrue);
  });

  test('flush delivers an event emitted by another event\'s handler within the same call', () {
    final bus = EventBus();
    bus.on<_EventA>((_) => bus.emit(const _EventB()));
    var receivedB = false;
    bus.on<_EventB>((_) => receivedB = true);

    bus.emit(const _EventA());
    bus.flush();

    expect(receivedB, isTrue, reason: 'cascading events resolve within the same flush, not one tick later');
  });

  test('flush handles a chain several events deep in one call', () {
    final bus = EventBus();
    final order = <int>[];
    bus.on<_EventA>((_) {
      order.add(1);
      bus.emit(const _EventB());
    });
    bus.on<_EventB>((_) => order.add(2));

    bus.emit(const _EventA());
    bus.flush();

    expect(order, [1, 2]);
  });

  test('flush does not hang on a genuine handler cycle', () {
    final bus = EventBus();
    var calls = 0;
    bus.on<_EventA>((_) {
      calls++;
      bus.emit(const _EventB());
    });
    bus.on<_EventB>((_) {
      calls++;
      bus.emit(const _EventA());
    });

    bus.emit(const _EventA());
    bus.flush();

    // Bounded by the cascade-round cap, not infinite.
    expect(calls, lessThan(100));
  });

  test('clearHandlers removes every registered handler', () {
    final bus = EventBus();
    var received = false;
    bus.on<_EventA>((_) => received = true);
    bus.clearHandlers();

    bus.emit(const _EventA());
    bus.flush();

    expect(received, isFalse);
  });
}
