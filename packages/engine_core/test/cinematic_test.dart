import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _buildWorld() => World(width: 100, height: 100);

void main() {
  group('WaitStep', () {
    test('completes once elapsed reaches duration, not before', () {
      final step = WaitStep(1);
      expect(step.update(_buildWorld(), 0.5), isFalse);
      expect(step.update(_buildWorld(), 0.4), isFalse);
      expect(step.update(_buildWorld(), 0.1), isTrue);
    });

    test('skip jumps straight to complete', () {
      final step = WaitStep(5);
      step.skip(_buildWorld());
      expect(step.update(_buildWorld(), 0), isTrue);
    });
  });

  group('CallbackStep', () {
    test('runs action once on start, completes on first update', () {
      var calls = 0;
      final step = CallbackStep((world) => calls++);
      final world = _buildWorld();
      step.start(world);
      expect(calls, 1);
      expect(step.update(world, 0.016), isTrue);
      expect(calls, 1);
    });
  });

  group('TweenStep', () {
    test('reports eased progress via onUpdate and completes at duration', () {
      final values = <double>[];
      final step = TweenStep(duration: 1, onUpdate: (world, t) => values.add(t));
      final world = _buildWorld();

      expect(step.update(world, 0.5), isFalse);
      expect(step.update(world, 0.5), isTrue);

      expect(values, [0.5, 1.0]);
    });

    test('skip reports progress 1.0', () {
      final values = <double>[];
      final step = TweenStep(duration: 1, onUpdate: (world, t) => values.add(t));
      step.skip(_buildWorld());
      expect(values, [1.0]);
    });
  });

  group('CinematicSystem', () {
    test('runs steps in order, one active at a time', () {
      final order = <String>[];
      final steps = [
        CallbackStep((w) => order.add('a-start')),
        CallbackStep((w) => order.add('b-start')),
      ];
      final system = CinematicSystem(steps);
      final world = _buildWorld();

      system.update(world, 0.016); // starts+completes step a
      system.update(world, 0.016); // starts+completes step b

      expect(order, ['a-start', 'b-start']);
    });

    test('isPlaying is true until every step completes, then false', () {
      final system = CinematicSystem([WaitStep(1), WaitStep(1)]);
      final world = _buildWorld();

      expect(system.isPlaying, isTrue);
      system.update(world, 1); // completes step 1, starts step 2
      expect(system.isPlaying, isTrue);
      system.update(world, 1); // completes step 2
      expect(system.isPlaying, isFalse);
    });

    test('emits CinematicCompleteEvent exactly once when the last step finishes', () {
      final system = CinematicSystem([WaitStep(1)]);
      final world = _buildWorld();
      var completions = 0;
      world.events.on<CinematicCompleteEvent>((_) => completions++);

      system.update(world, 1);
      world.events.flush();
      system.update(world, 1); // already done -- must not fire again
      world.events.flush();

      expect(completions, 1);
    });

    test('an empty step list completes immediately', () {
      final system = CinematicSystem([]);
      final world = _buildWorld();
      var completed = false;
      world.events.on<CinematicCompleteEvent>((_) => completed = true);

      system.update(world, 0.016);
      world.events.flush();

      expect(system.isPlaying, isFalse);
      expect(completed, isTrue);
    });

    test('skip calls skip on the current and every remaining step, then completes', () {
      final steps = [WaitStep(10), WaitStep(10), WaitStep(10)];
      final system = CinematicSystem(steps);
      final world = _buildWorld();
      system.update(world, 0.016); // starts step 0, not yet complete

      var completed = false;
      world.events.on<CinematicCompleteEvent>((_) => completed = true);

      system.skip(world);
      world.events.flush();

      expect(system.isPlaying, isFalse);
      expect(completed, isTrue);
      // Every step (including the ones never `start`ed) is now at its
      // end state -- verified indirectly: a fresh update() call is a
      // no-op, since the system is already done.
      system.update(world, 100);
      expect(system.isPlaying, isFalse);
    });

    test('skip on an already-done system is a no-op (no duplicate event)', () {
      final system = CinematicSystem([WaitStep(1)]);
      final world = _buildWorld();
      system.update(world, 1);
      world.events.flush(); // drain the real completion, unrelated to this test

      var completions = 0;
      world.events.on<CinematicCompleteEvent>((_) => completions++);

      system.skip(world);
      world.events.flush();

      expect(completions, 0);
    });

    test('CinematicSystem drives real gameplay data: a TweenStep moving a Position', () {
      final world = _buildWorld();
      registerCoreComponents(world);
      final rig = world.spawn();
      world.storeOf<Position>().set(rig, Position(0, 0));

      final system = CinematicSystem([
        TweenStep(
          duration: 2,
          onUpdate: (w, t) => w.storeOf<Position>().set(rig, Position(100 * t, 0)),
        ),
      ]);

      system.update(world, 1);
      expect(world.storeOf<Position>().get(rig)!.x, 50);

      system.update(world, 1);
      expect(world.storeOf<Position>().get(rig)!.x, 100);
      expect(system.isPlaying, isFalse);
    });
  });
}
