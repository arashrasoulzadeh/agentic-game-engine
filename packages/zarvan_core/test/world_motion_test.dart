import 'package:zarvan_core/zarvan_core.dart';
import 'package:test/test.dart';

void main() {
  World w() => World(width: 10, height: 10);

  test('tween eases, ends exactly on target, then fires onDone once', () {
    final world = w();
    final seen = <double>[];
    var done = 0;
    world.tween(
      0,
      100,
      1,
      seen.add,
      easing: EasingType.easeOutQuad,
      onDone: () => done++,
    );
    for (var i = 0; i < 5; i++) {
      world.step(0.25);
    }
    expect(seen.length, 4);
    expect(seen.first, closeTo(43.75, 1e-9));
    expect(seen.last, 100);
    expect(done, 1);
  });

  test('tween can be cancelled and rejects a negative duration', () {
    final world = w();
    var calls = 0;
    final h = world.tween(0, 1, 1, (_) => calls++);
    world.step(0.1);
    h.cancel();
    world.step(0.1);
    expect(calls, 1);
    expect(() => world.tween(0, 1, -1, (_) {}), throwsArgumentError);
  });

  test('sequence runs waits and actions in order on simulated time', () {
    final world = w();
    final log = <String>[];
    world.sequence([
      SeqStep.run(() => log.add('a')),
      const SeqStep.wait(1),
      SeqStep.run(() => log.add('b')),
      const SeqStep.wait(2),
      SeqStep.run(() => log.add('c')),
    ]);
    world.step(0.5);
    expect(log, ['a']);
    world.step(0.5);
    expect(log, ['a', 'b']);
    world.step(1.9);
    expect(log, ['a', 'b']);
    world.step(0.1);
    expect(log, ['a', 'b', 'c']);
    world.step(5);
    expect(log.length, 3);
  });

  test('sequence stops when cancelled', () {
    final world = w();
    var ran = 0;
    final h = world.sequence([const SeqStep.wait(1), SeqStep.run(() => ran++)]);
    h.cancel();
    world.step(2);
    expect(ran, 0);
  });
}
