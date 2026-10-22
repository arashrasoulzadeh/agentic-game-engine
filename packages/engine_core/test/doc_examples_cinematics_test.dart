// The cinematic samples in docs/concepts/cinematics.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  late World world;
  setUp(() {
    world = World(width: 100, height: 100);
    registerCoreComponents(world);
    world.storeOf<GameState>().set(0, GameState());
  });

  test('a script runs its steps in order, then announces completion', () {
    final events = <String>[];
    world.events.on<CinematicCompleteEvent>((_) => events.add('done'));

    final cinematic = CinematicSystem([
      CallbackStep((w) => events.add('show line')),
      WaitStep(1.5),
      TweenStep(
        duration: 2,
        easing: EasingType.easeInOutQuad,
        onUpdate: (w, t) => events.add('t=${t.toStringAsFixed(1)}'),
      ),
      SetFlagStep(flag: 'intro_seen'),
    ]);
    world.addSystem(cinematic);

    expect(cinematic.isPlaying, isTrue);
    for (var i = 0; i < 400 && cinematic.isPlaying; i++) {
      world.step(0.02);
    }
    expect(cinematic.isPlaying, isFalse);
    expect(events.first, 'show line');
    expect(events.last, 'done');
    expect(events, contains('t=1.0'));
    expect(
      events.indexOf('show line'),
      lessThan(events.indexWhere((e) => e.startsWith('t='))),
    );
  });

  test('skip leaves every step in its end state and completes at once', () {
    var tweenEnd = -1.0;
    var done = 0;
    world.events.on<CinematicCompleteEvent>((_) => done++);
    final cinematic = CinematicSystem([
      WaitStep(100),
      TweenStep(duration: 5, onUpdate: (w, t) => tweenEnd = t),
    ]);
    world.addSystem(cinematic);
    world.step(0.1);

    cinematic.skip(world);
    world.step(0.0);
    expect(tweenEnd, 1.0);
    expect(cinematic.isPlaying, isFalse);
    expect(done, 1);
  });

  test('a step can be added while the cinematic is still playing', () {
    final ran = <String>[];
    final cinematic = CinematicSystem([
      CallbackStep((w) => ran.add('a')),
      WaitStep(1),
    ]);
    world.addSystem(cinematic);
    world.step(0.1);
    cinematic.addStep(CallbackStep((w) => ran.add('b')));
    for (var i = 0; i < 30; i++) {
      world.step(0.1);
    }
    expect(ran, ['a', 'b']);
    expect(cinematic.isPlaying, isFalse);
  });
}
