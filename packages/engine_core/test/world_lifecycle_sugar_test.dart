import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

class _Ping {}

class _Noop implements System {
  int runs = 0;
  @override
  String get name => 'noop';
  @override
  void update(World world, double dt) => runs++;
}

World _world() {
  final w = World(width: 100, height: 100);
  registerCoreComponents(w);
  return w;
}

void main() {
  test('world.on and world.once subscribe to the bus', () {
    final w = _world();
    var all = 0, first = 0;
    w.on<_Ping>((_) => all++);
    w.once<_Ping>((_) => first++);
    w.events.emit(_Ping());
    w.events.emit(_Ping());
    w.events.flush();
    expect([all, first], [2, 1]);
  });

  test('setComponents writes all, rejects dead, unregistered, duplicate', () {
    final w = _world();
    final id = w.spawn();
    w.setComponents(id, [Position(1, 2), Velocity(3, 4)]);
    expect(w.getComponent<Velocity>(id)!.x, 3);
    expect(
      () => w.setComponents(id, [Position(0, 0), Position(1, 1)]),
      throwsArgumentError,
    );
    expect(() => w.setComponents(id, [_Ping()]), throwsArgumentError);
    expect(
      w.getComponent<Position>(id)!.x,
      1,
      reason: 'a rejected batch writes nothing',
    );
    w.destroy(id);
    expect(() => w.setComponents(id, [Position(0, 0)]), throwsStateError);
  });

  test('dispose drops handlers, systems, timers and queued commands', () {
    final w = _world();
    final sys = _Noop();
    w.addSystem(sys);
    var heard = 0, fired = 0;
    w.on<_Ping>((_) => heard++);
    w.after(0, () => fired++);
    final id = w.spawn();
    w.commands.destroy(id);
    w.dispose();
    w.dispose();
    w.step(0.1);
    w.events.emit(_Ping());
    w.events.flush();
    expect([sys.runs, heard, fired], [0, 0, 0]);
    expect(w.commands.isEmpty, isTrue);
    expect(w.entities.isAlive(id), isTrue);
  });
}
