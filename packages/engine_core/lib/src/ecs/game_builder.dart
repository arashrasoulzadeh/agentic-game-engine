import 'behavior.dart';
import 'entity.dart';
import 'entity_builder.dart';
import 'fixed_stepper.dart';
import 'system_presets.dart';
import 'world.dart';
import '../../engine_core.dart' show registerCoreComponents;

/// One-call setup for a simulation: a [World] with components registered,
/// the core systems installed and an optional fixed-timestep loop.
///
/// ```dart
/// final game = GameBuilder.create(width: 320, height: 240);
/// game.world.spawnWith([Position(10, 10), Velocity(60, 0)]);
/// game.update(1 / 60); // call once per frame
/// ```
///
/// Everything it does is plain `World` API, so nothing here is hidden magic:
/// reach for `game.world` whenever you need more.
abstract final class GameBuilder {
  /// Creates the world and wraps it in a [GameLoop].
  ///
  /// - [seed] seeds `world.random` (default 0 = reproducible).
  /// - [fixedStep], if given, makes [GameLoop.update] simulate in whole steps
  ///   of that many seconds regardless of frame rate.
  /// - [behaviors] enables entity AI.
  /// - [presets] false skips [SystemPresets.core] so you can add only the
  ///   systems you want.
  /// - [register] lists extra component registrations, e.g.
  ///   `[registerFlutterComponents]` in a Flutter game; core's own are always
  ///   registered (call `registerCoreComponents` yourself if you build a
  ///   world without this class).
  static GameLoop create({
    required double width,
    required double height,
    int seed = 0,
    double? fixedStep,
    BehaviorRegistry? behaviors,
    bool presets = true,
    List<void Function(World world)> register = const [],
  }) {
    final world = World(width: width, height: height, seed: seed);
    registerCoreComponents(world);
    for (final registrar in register) {
      registrar(world);
    }
    if (presets) SystemPresets.core(world, behaviors: behaviors);
    return GameLoop(
      world,
      stepper: fixedStep == null ? null : FixedStepper(fixedStep),
    );
  }
}

/// Drives a [World] from your frame loop, with pause and stop.
class GameLoop {
  /// The simulation. Use it directly for anything not wrapped here.
  final World world;

  /// Present when a fixed step was requested.
  final FixedStepper? stepper;

  bool _paused = false;
  bool _stopped = false;

  GameLoop(this.world, {this.stepper});

  /// Whether [update] is currently ignored.
  bool get isPaused => _paused;

  /// Whether [stop] has been called; a stopped loop never runs again.
  bool get isStopped => _stopped;

  /// Advances the simulation by [frameSeconds] of real time and returns how
  /// many world steps ran (0 while paused or stopped, or while a fixed step
  /// is still accumulating). Without a fixed step it is one step of
  /// [frameSeconds].
  int update(double frameSeconds) {
    if (_paused || _stopped) return 0;
    final stepper = this.stepper;
    if (stepper == null) {
      world.step(frameSeconds);
      return 1;
    }
    return stepper.advance(frameSeconds, world.step);
  }

  /// Stops [update] from advancing time until [resume]. Timers, which follow
  /// simulated time, pause with it.
  void pause() => _paused = true;

  /// Undoes [pause]. Time spent paused is not replayed.
  void resume() {
    _paused = false;
    stepper?.reset();
  }

  /// Ends the loop for good and releases the world's resources.
  void stop() {
    if (_stopped) return;
    _stopped = true;
    world.dispose();
  }

  /// Shortcut for `world.spawnAt`.
  EntityId spawnAt(double x, double y) => world.spawnAt(x, y);

  /// Shortcut for `world.spawnWith`.
  EntityId spawn(Iterable<Object> components) => world.spawnWith(components);

  /// Shortcut for `world.entity()`.
  EntityBuilder entity() => world.entity();
}
