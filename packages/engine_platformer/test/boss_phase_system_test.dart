import 'package:engine_core/engine_core.dart';
import 'package:engine_platformer/engine_platformer.dart';
import 'package:flutter_test/flutter_test.dart';

World _buildWorld() {
  final world = World(width: 500, height: 500);
  registerCoreComponents(world);
  registerPlatformerComponents(world);
  return world;
}

void main() {
  test('constructor rejects phases not given in descending healthFraction order', () {
    expect(
      () => BossPhaseSystem(1, [
        BossPhase(healthFraction: 0.5, patternId: 'a'),
        BossPhase(healthFraction: 0.75, patternId: 'b'),
      ]),
      throwsArgumentError,
    );
  });

  test('constructor accepts phases in descending order, including ties', () {
    expect(
      () => BossPhaseSystem(1, [
        BossPhase(healthFraction: 0.75, patternId: 'a'),
        BossPhase(healthFraction: 0.75, patternId: 'b'),
        BossPhase(healthFraction: 0.25, patternId: 'c'),
      ]),
      returnsNormally,
    );
  });

  test('does nothing while health stays above every phase threshold', () {
    final world = _buildWorld();
    final boss = world.spawn();
    world.storeOf<Health>().set(boss, Health(current: 100, max: 100));
    final system = BossPhaseSystem(boss, [BossPhase(healthFraction: 0.5, patternId: 'enraged')]);
    world.addSystem(system);

    BossPhaseChangedEvent? seen;
    world.events.on<BossPhaseChangedEvent>((e) => seen = e);

    world.step(0.016);

    expect(seen, isNull);
  });

  test('fires BossPhaseChangedEvent the tick health first drops to/below a threshold', () {
    final world = _buildWorld();
    final boss = world.spawn();
    final health = Health(current: 100, max: 100);
    world.storeOf<Health>().set(boss, health);
    final system = BossPhaseSystem(boss, [BossPhase(healthFraction: 0.5, patternId: 'enraged')]);
    world.addSystem(system);

    BossPhaseChangedEvent? seen;
    world.events.on<BossPhaseChangedEvent>((e) => seen = e);

    health.current = 50; // exactly at the threshold
    world.step(0.016);

    expect(seen, isNotNull);
    expect(seen!.entity, boss);
    expect(seen!.patternId, 'enraged');
    expect(seen!.phaseIndex, 0);
  });

  test('a phase fires only once even if health rises back above the threshold', () {
    final world = _buildWorld();
    final boss = world.spawn();
    final health = Health(current: 100, max: 100);
    world.storeOf<Health>().set(boss, health);
    final system = BossPhaseSystem(boss, [BossPhase(healthFraction: 0.5, patternId: 'enraged')]);
    world.addSystem(system);

    var fireCount = 0;
    world.events.on<BossPhaseChangedEvent>((e) => fireCount++);

    health.current = 40;
    world.step(0.016);
    expect(fireCount, 1);

    health.current = 90; // healed back up
    world.step(0.016);
    health.current = 30; // dropped again, still below the same threshold
    world.step(0.016);

    expect(fireCount, 1, reason: 'a phase that already triggered never re-triggers');
  });

  test('multiple phases fire in order as health crosses each threshold on separate ticks', () {
    final world = _buildWorld();
    final boss = world.spawn();
    final health = Health(current: 100, max: 100);
    world.storeOf<Health>().set(boss, health);
    final system = BossPhaseSystem(boss, [
      BossPhase(healthFraction: 0.75, patternId: 'phase1'),
      BossPhase(healthFraction: 0.5, patternId: 'phase2'),
      BossPhase(healthFraction: 0.25, patternId: 'phase3'),
    ]);
    world.addSystem(system);

    final fired = <String>[];
    world.events.on<BossPhaseChangedEvent>((e) => fired.add(e.patternId));

    health.current = 70;
    world.step(0.016);
    health.current = 40;
    world.step(0.016);
    health.current = 10;
    world.step(0.016);

    expect(fired, ['phase1', 'phase2', 'phase3']);
  });

  test('a single hit crossing multiple thresholds at once fires every crossed phase in order', () {
    final world = _buildWorld();
    final boss = world.spawn();
    final health = Health(current: 100, max: 100);
    world.storeOf<Health>().set(boss, health);
    final system = BossPhaseSystem(boss, [
      BossPhase(healthFraction: 0.75, patternId: 'phase1'),
      BossPhase(healthFraction: 0.5, patternId: 'phase2'),
      BossPhase(healthFraction: 0.25, patternId: 'phase3'),
    ]);
    world.addSystem(system);

    final fired = <String>[];
    world.events.on<BossPhaseChangedEvent>((e) => fired.add(e.patternId));

    health.current = 5; // crosses all three thresholds in one hit
    world.step(0.016);

    expect(fired, ['phase1', 'phase2', 'phase3']);
  });

  test('with no Health component, is a harmless no-op', () {
    final world = _buildWorld();
    final boss = world.spawn(); // no Health
    final system = BossPhaseSystem(boss, [BossPhase(healthFraction: 0.5, patternId: 'x')]);
    world.addSystem(system);

    expect(() => world.step(0.016), returnsNormally);
  });

  group('cinematicSteps', () {
    test('a phase with no cinematicSteps leaves isInCinematic false', () {
      final world = _buildWorld();
      final boss = world.spawn();
      final health = Health(current: 100, max: 100);
      world.storeOf<Health>().set(boss, health);
      final system = BossPhaseSystem(boss, [BossPhase(healthFraction: 0.5, patternId: 'x')]);
      world.addSystem(system);

      health.current = 10;
      world.step(0.016);

      expect(system.isInCinematic, isFalse);
    });

    test('a phase with cinematicSteps starts playing it, isInCinematic true until it '
        'completes', () {
      final world = _buildWorld();
      final boss = world.spawn();
      final health = Health(current: 100, max: 100);
      world.storeOf<Health>().set(boss, health);
      var built = 0;
      final system = BossPhaseSystem(boss, [
        BossPhase(
          healthFraction: 0.5,
          patternId: 'x',
          cinematicSteps: () {
            built++;
            return [WaitStep(0.05)];
          },
        ),
      ]);
      world.addSystem(system);

      health.current = 10;
      world.step(0.016); // triggers the phase, cinematic assigned but not yet ticked
      expect(built, 1);

      world.step(0.016); // starts the WaitStep
      expect(system.isInCinematic, isTrue);

      // Enough further ticks for the 0.05s WaitStep to complete.
      world.step(0.02);
      world.step(0.02);
      world.step(0.02);

      expect(system.isInCinematic, isFalse);
    });
  });
}
