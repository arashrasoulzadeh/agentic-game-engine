import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

class _Ping {
  final int n;
  _Ping(this.n);
}

void main() {
  late EventBus bus;
  setUp(() => bus = EventBus());

  test('cancel stops delivery and is idempotent', () {
    var hits = 0;
    final sub = bus.on<_Ping>((_) => hits++);
    expect(sub.isActive, isTrue);
    bus.emit(_Ping(1));
    bus.flush();
    sub.cancel();
    sub.cancel();
    expect(sub.isActive, isFalse);
    bus.emit(_Ping(2));
    bus.flush();
    expect(hits, 1);
  });

  test(
    'a handler can cancel itself: events already queued are not delivered',
    () {
      var hits = 0;
      late Subscription sub;
      sub = bus.on<_Ping>((_) {
        hits++;
        sub.cancel();
      });
      bus
        ..emit(_Ping(1))
        ..emit(_Ping(2));
      bus.flush();
      expect(hits, 1);
    },
  );

  test('a handler can cancel a later handler of the same event', () {
    final log = <String>[];
    late Subscription second;
    bus.on<_Ping>((_) {
      log.add('first');
      second.cancel();
    });
    second = bus.on<_Ping>((_) => log.add('second'));
    bus
      ..emit(_Ping(1))
      ..emit(_Ping(2));
    bus.flush();
    expect(log, ['first', 'first']);
  });

  test('once runs at most once even when the event is emitted twice', () {
    var hits = 0;
    bus.once<_Ping>((_) => hits++);
    bus
      ..emit(_Ping(1))
      ..emit(_Ping(2));
    bus.flush();
    bus.emit(_Ping(3));
    bus.flush();
    expect(hits, 1);
  });

  test(
    'once cancels before calling, so re-emitting inside it does not loop',
    () {
      var hits = 0;
      bus.once<_Ping>((e) {
        hits++;
        bus.emit(_Ping(e.n + 1));
      });
      bus.emit(_Ping(0));
      bus.flush();
      expect(hits, 1);
    },
  );

  test('a handler added during a flush sees the next event, not this one, '
      'and does not break the running dispatch', () {
    final log = <String>[];
    var added = false;
    bus.on<_Ping>((e) {
      log.add('a:${e.n}');
      if (!added) {
        added = true;
        bus.on<_Ping>((e) => log.add('late:${e.n}'));
      }
    });
    bus
      ..emit(_Ping(1))
      ..emit(_Ping(2));
    bus.flush();
    expect(log, ['a:1', 'a:2', 'late:2']);
  });

  test('clearHandlers during a flush stops the remaining handlers', () {
    final log = <String>[];
    bus.on<_Ping>((_) {
      log.add('first');
      bus.clearHandlers();
    });
    bus.on<_Ping>((_) => log.add('second'));
    bus.emit(_Ping(1));
    bus.flush();
    expect(log, ['first']);
  });

  test('a throwing handler leaves the bus usable and cancels still prune', () {
    final log = <String>[];
    bus.on<_Ping>((_) => throw StateError('boom'));
    final other = bus.on<_Ping>((_) => log.add('other'));
    bus.emit(_Ping(1));
    expect(bus.flush, throwsStateError);
    other.cancel();
    bus.emit(_Ping(2));
    expect(bus.flush, throwsStateError);
    expect(log, isEmpty);
  });

  test('subscriptions to different types are independent', () {
    var pings = 0;
    var strings = 0;
    final p = bus.on<_Ping>((_) => pings++);
    bus.on<String>((_) => strings++);
    p.cancel();
    bus
      ..emit(_Ping(1))
      ..emit('x');
    bus.flush();
    expect([pings, strings], [0, 1]);
  });
}
