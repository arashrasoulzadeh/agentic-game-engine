import 'dart:convert';

import '../../engine_core.dart';

/// A headless driver for testing game logic: build a world, step it in whole
/// ticks, look at what happened.
///
/// ```dart
/// final t = GameTester(width: 100, height: 100);
/// final ball = t.world.spawnWith([Position(0, 0), Velocity(60, 0)]);
/// t.advance(1);                         // one simulated second
/// expect(t.component<Position>(ball).x, closeTo(60, 1));
/// ```
///
/// Everything is deterministic: time only moves when you call [tick] or
/// [advance], and `world.random` is seeded.
class GameTester {
  /// The loop under test; use [world] for direct access.
  final GameLoop game;

  /// Seconds per tick for [tick] and [advance].
  final double dt;

  GameTester({
    double width = 800,
    double height = 600,
    int seed = 0,
    this.dt = 1 / 60,
    bool presets = true,
    BehaviorRegistry? behaviors,
    List<void Function(World world)> register = const [],
  }) : game = GameBuilder.create(
         width: width,
         height: height,
         seed: seed,
         presets: presets,
         behaviors: behaviors,
         register: register,
       );

  /// The simulation.
  World get world => game.world;

  /// Runs exactly [count] world steps of [dt] seconds.
  void tick([int count = 1]) {
    if (count < 0) throw ArgumentError.value(count, 'count', 'must be >= 0');
    for (var i = 0; i < count; i++) {
      world.step(dt);
    }
  }

  /// Runs enough ticks to cover [seconds] of simulated time (rounded to the
  /// nearest whole tick) and returns how many ran.
  int advance(double seconds) {
    if (seconds < 0) throw ArgumentError.value(seconds, 'seconds', '>= 0');
    final count = (seconds / dt).round();
    tick(count);
    return count;
  }

  /// Steps until [done] returns true, at most [maxTicks] times; returns the
  /// ticks run. Throws [StateError] naming [description] if it never became
  /// true, with [World.debug] attached, which beats an infinite loop.
  int tickUntil(
    bool Function() done, {
    int maxTicks = 100000,
    String description = 'the condition',
  }) {
    for (var i = 0; i < maxTicks; i++) {
      if (done()) return i;
      world.step(dt);
    }
    if (done()) return maxTicks;
    throw StateError(
      'Gave up waiting for $description after $maxTicks ticks.\n'
      '${world.debug()}',
    );
  }

  /// [entity]'s [T]; throws a [StateError] that says what the entity does have
  /// (more useful in a test than a null).
  T component<T>(EntityId entity) {
    final value = world.getComponent<T>(entity);
    if (value != null) return value;
    final have = world.components.serializeEntity(entity).keys.toList()..sort();
    throw StateError(
      'Entity $entity has no $T. It has: ${have.isEmpty ? 'nothing' : have.join(', ')}'
      '${world.entities.isAlive(entity) ? '' : ' (it is not alive)'}.',
    );
  }

  /// Collects every event of type [E] emitted from now on. The returned list
  /// grows as the world steps.
  List<E> record<E>() {
    final events = <E>[];
    world.events.on<E>(events.add);
    return events;
  }

  /// The world as stable, human-diffable text: the [World.save] JSON with keys
  /// sorted and two-space indentation. Compare it to a golden file with
  /// [expectGolden].
  String snapshotText() => canonicalJson(world.save());

  /// [World.debug], for failure messages.
  String describe() => world.debug();
}

/// [value] as JSON with every map's keys sorted and two-space indentation, so
/// equal data always prints identically.
String canonicalJson(Object? value) =>
    const JsonEncoder.withIndent('  ').convert(_sorted(value));

Object? _sorted(Object? v) {
  if (v is Map) {
    final entries = v.entries.toList()
      ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    return {for (final e in entries) '${e.key}': _sorted(e.value)};
  }
  if (v is List) return [for (final e in v) _sorted(e)];
  return v;
}
