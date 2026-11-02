import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Ping {}

class _Sys implements System {
  @override
  String get name => 'same';
  @override
  void update(World world, double dt) {}
}

World _world() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  w.warnings.clear();
  return w;
}

void main() {
  test('duplicate system names warn', () {
    final w = _world();
    w.addSystem(_Sys());
    expect(w.warnings.messages, isEmpty);
    w.addSystem(_Sys());
    expect(w.warnings.messages.single, contains('"same"'));
  });

  test('re-registering a component warns, first registration does not', () {
    final w = _world();
    registerCoreComponents(w);
    expect(w.warnings.messages.first, contains('registered again'));
    final fresh = World(width: 1, height: 1);
    registerCoreComponents(fresh);
    expect(fresh.warnings.messages, isEmpty);
  });

  test('unhandled events warn only when asked to', () {
    final w = _world();
    w.events.emit(_Ping());
    w.events.flush();
    expect(w.warnings.messages, isEmpty);
    w.warnOnUnhandledEvents = true;
    w.events.emit(_Ping());
    w.events.flush();
    expect(w.warnings.messages.single, contains('_Ping'));
    w.on<_Ping>((_) {});
    w.events.emit(_Ping());
    w.events.flush();
    expect(w.warnings.messages.length, 1, reason: 'handled now');
    w.warnOnUnhandledEvents = false;
  });

  test('disabled warnings record nothing; onWarning and debug() see them', () {
    final w = _world();
    final seen = <String>[];
    w.warnings.onWarning = seen.add;
    w.addSystem(_Sys());
    w.addSystem(_Sys());
    expect(seen, hasLength(1));
    expect(w.debug(), contains('warnings (1)'));
    w.warnings.enabled = false;
    w.addSystem(_Sys());
    expect(seen, hasLength(1));
  });

  test('an identical repeat is not recorded twice in a row', () {
    final w = _world();
    w.warnings.warn('same');
    w.warnings.warn('same');
    expect(w.warnings.messages, hasLength(1));
  });
}
