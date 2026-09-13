import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() {
  final world = World(width: 100, height: 100);
  registerCoreComponents(world);
  world.addSystem(TweenSystem());
  return world;
}

void main() {
  test('name identifies this system in World.systemOrder', () {
    final world = _buildWorld();
    expect(world.systemOrder, contains('tween'));
  });

  test('value interpolates linearly from from to to over duration', () {
    final tween = Tween(from: 0, to: 10, duration: 2, elapsed: 1);
    expect(tween.value, 5);
    expect(tween.rawProgress, 0.5);
  });

  test('easeInQuad/easeOutQuad/easeInOutQuad differ from linear mid-progress', () {
    final linear = Tween(from: 0, to: 10, duration: 1, elapsed: 0.5);
    final easeIn = Tween(from: 0, to: 10, duration: 1, elapsed: 0.5, easing: EasingType.easeInQuad);
    final easeOut =
        Tween(from: 0, to: 10, duration: 1, elapsed: 0.5, easing: EasingType.easeOutQuad);
    final easeInOut =
        Tween(from: 0, to: 10, duration: 1, elapsed: 0.5, easing: EasingType.easeInOutQuad);

    expect(linear.value, 5);
    expect(easeIn.value, lessThan(5));
    expect(easeOut.value, greaterThan(5));
    expect(easeInOut.value, closeTo(5, 0.001)); // symmetric curve at t=0.5
  });

  test('isComplete is false while running, true once elapsed reaches duration', () {
    final tween = Tween(from: 0, to: 1, duration: 1, elapsed: 0.9);
    expect(tween.isComplete, isFalse);
    tween.elapsed = 1;
    expect(tween.isComplete, isTrue);
  });

  test('a loop/pingPong tween is never "complete"', () {
    expect(Tween(from: 0, to: 1, duration: 1, elapsed: 1, loop: true).isComplete, isFalse);
    expect(Tween(from: 0, to: 1, duration: 1, elapsed: 1, pingPong: true).isComplete, isFalse);
  });

  test('TweenSystem advances elapsed and clamps a plain tween at duration', () {
    final world = _buildWorld();
    final id = world.spawn();
    final tween = Tween(from: 0, to: 10, duration: 1);
    world.storeOf<Tween>().set(id, tween);

    world.step(0.5);
    expect(tween.elapsed, closeTo(0.5, 0.001));

    world.step(1); // overshoots duration
    expect(tween.elapsed, 1); // clamped, not left at 1.5
    expect(tween.value, 10);
  });

  test('TweenSystem emits TweenCompleteEvent exactly once', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Tween>().set(id, Tween(from: 0, to: 1, duration: 0.1));

    var completions = 0;
    world.events.on<TweenCompleteEvent>((e) {
      if (e.entity == id) completions++;
    });

    world.step(0.2); // crosses duration this tick
    world.step(0.2); // already complete -- must not fire again
    world.step(0.2);

    expect(completions, 1);
  });

  test('TweenSystem wraps a looping tween back to 0 instead of clamping', () {
    final world = _buildWorld();
    final id = world.spawn();
    final tween = Tween(from: 0, to: 1, duration: 1, loop: true);
    world.storeOf<Tween>().set(id, tween);

    world.step(1.25);
    expect(tween.elapsed, closeTo(0.25, 0.001));
  });

  test('TweenSystem flips reversed at each end of a pingPong tween', () {
    final world = _buildWorld();
    final id = world.spawn();
    final tween = Tween(from: 0, to: 10, duration: 1, pingPong: true);
    world.storeOf<Tween>().set(id, tween);

    expect(tween.reversed, isFalse);
    world.step(1.2); // crosses duration -> flips, elapsed wraps
    expect(tween.reversed, isTrue);
    expect(tween.elapsed, closeTo(0.2, 0.001));
    // Reversed: value should now be counting back down from `to`.
    expect(tween.value, lessThan(10));
  });

  test('a zero-duration tween does not divide by zero and settles at "to"', () {
    final tween = Tween(from: 0, to: 5, duration: 0);
    expect(tween.rawProgress, 1);
    expect(tween.value, 5);
    expect(tween.isComplete, isTrue);
  });

  test('TweenSystem advancing a zero-duration tween does not throw or loop forever', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Tween>().set(id, Tween(from: 0, to: 5, duration: 0, loop: true));

    expect(() => world.step(0.1), returnsNormally);
  });

  test('Tween round-trips through toJson/fromJson', () {
    final tween = Tween(
      from: 1,
      to: 2,
      duration: 3,
      elapsed: 1.5,
      loop: true,
      pingPong: false,
      easing: EasingType.easeOutQuad,
      reversed: true,
    );
    final restored = Tween.fromJson(tween.toJson());

    expect(restored.from, 1);
    expect(restored.to, 2);
    expect(restored.duration, 3);
    expect(restored.elapsed, 1.5);
    expect(restored.loop, isTrue);
    expect(restored.pingPong, isFalse);
    expect(restored.easing, EasingType.easeOutQuad);
    expect(restored.reversed, isTrue);
  });

  test('Tween.fromJson defaults optional fields when absent', () {
    final restored = Tween.fromJson({'from': 0, 'to': 1, 'duration': 1});
    expect(restored.elapsed, 0);
    expect(restored.loop, isFalse);
    expect(restored.pingPong, isFalse);
    expect(restored.easing, EasingType.linear);
    expect(restored.reversed, isFalse);
  });

  test('Tween serializes through World.toJson via registerCoreComponents', () {
    final world = _buildWorld();
    final id = world.spawn();
    world.storeOf<Tween>().set(id, Tween(from: 0, to: 1, duration: 1));

    final snapshot = world.toJson();
    final entity = (snapshot['entities'] as List).first as Map;
    expect((entity['components'] as Map)['tween']['to'], 1);
  });
}
