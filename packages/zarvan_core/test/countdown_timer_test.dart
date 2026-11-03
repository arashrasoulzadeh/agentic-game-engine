import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

World _world() {
  final world = World(width: 10, height: 10);
  registerCoreComponents(world);
  world.addSystem(CountdownTimerSystem());
  return world;
}

List<CountdownTimerFired> _listen(World world) {
  final fired = <CountdownTimerFired>[];
  world.events.on<CountdownTimerFired>(fired.add);
  return fired;
}

void main() {
  test('a one-shot fires once at zero and removes itself', () {
    final world = _world();
    final fired = _listen(world);
    final id = world.spawnWith([CountdownTimer('boom', 0.25)]);
    world.step(0.1);
    world.step(0.1);
    expect(fired, isEmpty);
    world.step(0.1);
    expect(fired.single.name, 'boom');
    expect(fired.single.entity, id);
    expect(world.hasComponent<CountdownTimer>(id), isFalse);
    world.step(0.1);
    expect(fired, hasLength(1));
  });

  test('a repeating timer keeps firing, once per elapsed interval', () {
    final world = _world();
    final fired = _listen(world);
    final id = world.spawnWith([CountdownTimer('tick', 0.1, interval: 0.1)]);
    world.step(0.5);
    expect(fired, hasLength(5));
    expect(world.hasComponent<CountdownTimer>(id), isTrue);
  });

  test('the timer round-trips through JSON and resumes where it was', () {
    final world = _world();
    final id = world.spawnWith([CountdownTimer('save', 1.0)]);
    world.step(0.4);
    final saved = world.toJson();

    final other = _world();
    final fired = _listen(other);
    other.entities.ensureAlive(id);
    other.applyPatch(saved);
    expect(
      other.getComponent<CountdownTimer>(id)!.remaining,
      closeTo(0.6, 1e-9),
    );
    other.step(0.5);
    expect(fired, isEmpty);
    other.step(0.2);
    expect(fired.single.name, 'save');
  });

  test('a snapshot restore rewinds the timer', () {
    final world = _world();
    final id = world.spawnWith([CountdownTimer('t', 1.0)]);
    final snap = WorldSnapshot.capture(world);
    world.step(0.6);
    snap.restoreInto(world);
    expect(world.getComponent<CountdownTimer>(id)!.remaining, 1.0);
  });

  test('several timers on different entities are independent', () {
    final world = _world();
    final fired = _listen(world);
    world.spawnWith([CountdownTimer('a', 0.1)]);
    world.spawnWith([CountdownTimer('b', 0.3)]);
    world.step(0.1);
    expect(fired.map((f) => f.name), ['a']);
    world.step(0.2);
    expect(fired.map((f) => f.name), ['a', 'b']);
  });

  test('json omits interval for a one-shot', () {
    expect(CountdownTimer('x', 1).toJson().containsKey('interval'), isFalse);
    expect(CountdownTimer('x', 1, interval: 2).toJson()['interval'], 2);
  });
}
