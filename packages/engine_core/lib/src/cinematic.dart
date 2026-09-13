import 'components/tween.dart';
import 'system.dart';
import 'world.dart';

/// One step of a scripted, non-interactive sequence — see
/// `CinematicSystem`. [start] runs once when the step becomes active;
/// [update] runs every tick after that until it returns `true` (done).
///
/// [skip] is called instead of a final [update] when the whole
/// cinematic is skipped (`CinematicSystem.skip`) — it must leave the
/// world in the same *end* state [update] eventually would have,
/// without assuming [start] already ran (a step still to come when
/// `skip` is called never gets a normal [start]/[update]). This is
/// what makes "skip" honest rather than a fast-forwarded replay: each
/// step decides what "already at its end state" means for whatever
/// it's driving (a `Tween`'s value reaching 1.0, a line of dialogue
/// simply never showing) instead of the engine trying to simulate every
/// remaining tick instantly.
abstract class CinematicStep {
  void start(World world) {}
  bool update(World world, double dt);
  void skip(World world) {}
}

/// Waits [duration] seconds, then completes — pacing between other
/// steps (a pause before dialogue, a beat after a camera move lands).
class WaitStep extends CinematicStep {
  final double duration;
  double _elapsed = 0;

  WaitStep(this.duration);

  @override
  bool update(World world, double dt) {
    _elapsed += dt;
    return _elapsed >= duration;
  }

  @override
  void skip(World world) => _elapsed = duration;
}

/// Runs [action] once, then completes immediately — a one-off effect
/// with no duration of its own (show a line of dialogue, emit a
/// domain event, play a sound). Pair with a `WaitStep` after it if the
/// effect needs to stay up for a while (e.g. a dialogue box shown for
/// N seconds) rather than writing a dedicated `CinematicStep`.
class CallbackStep extends CinematicStep {
  final void Function(World world) action;

  CallbackStep(this.action);

  @override
  void start(World world) => action(world);

  @override
  bool update(World world, double dt) => true;
}

/// Drives a value from 0.0 to 1.0 over [duration] seconds (eased per
/// [easing]) and hands it to [onUpdate] every tick — the "doesn't hide
/// how it works" approach `Tween` itself takes: this step doesn't
/// presume what's being animated, so [onUpdate] is exactly where a game
/// applies the progress to a camera-rig entity's `Position`, a
/// `Sprite`'s alpha, or anything else. Internally reuses `Tween`'s own
/// easing math (a local, non-world-attached `Tween` instance) rather
/// than duplicating it.
///
/// Example — panning the camera by moving whatever entity
/// `Scene.cameraFollowEntity` points at:
/// ```dart
/// TweenStep(
///   duration: 2,
///   easing: EasingType.easeInOutQuad,
///   onUpdate: (world, t) {
///     final pos = world.storeOf<Position>().get(cameraRig)!;
///     world.storeOf<Position>().set(
///       cameraRig,
///       Position(startX + (endX - startX) * t, startY + (endY - startY) * t),
///     );
///   },
/// )
/// ```
class TweenStep extends CinematicStep {
  final double duration;
  final EasingType easing;
  final void Function(World world, double t) onUpdate;
  late final Tween _tween;

  TweenStep({
    required this.duration,
    this.easing = EasingType.linear,
    required this.onUpdate,
  }) {
    _tween = Tween(from: 0, to: 1, duration: duration, easing: easing);
  }

  @override
  bool update(World world, double dt) {
    _tween.elapsed += dt;
    onUpdate(world, _tween.value);
    return _tween.isComplete;
  }

  @override
  void skip(World world) {
    _tween.elapsed = _tween.duration;
    onUpdate(world, _tween.value);
  }
}

/// Fired once, the tick a `CinematicSystem` finishes every step (or is
/// skipped) — a game's cue to give input control back to the player
/// (see `CinematicSystem`'s doc comment).
class CinematicCompleteEvent {
  const CinematicCompleteEvent();
}

/// Plays [steps] in order, one at a time — the engine's mechanism for a
/// scripted, non-interactive sequence (a cutscene on level start, a
/// boss intro, an ending), built on primitives that already exist
/// (`Tween`'s easing math, `EventBus`) rather than a new top-level
/// concept. Works the same whether used for a dedicated cutscene
/// `Scene` or a scripted beat inside an otherwise-playable level (a
/// door opening, a boss's intro animation) — it's just a `System` like
/// any other, added via `world.addSystem(...)`.
///
/// **Taking/returning input control**: this system has no opinion on
/// input — a game reads [isPlaying] in whatever gates its own
/// input-driven systems (e.g. skip adding `PlatformerInputSystem`'s
/// input reads, or check `isPlaying` in a custom wrapper System) before
/// letting player input move anything, and resumes once
/// `CinematicCompleteEvent` fires. Keeping that decision in the game's
/// hands matches how `SceneController.pushOverlay` leaves "what the
/// overlay shows" entirely to the game — the engine only owns
/// sequencing here, never what a cinematic actually does.
///
/// **Skipping**: call [skip] (e.g. from a "SKIP" button/key a game
/// wires up) to jump straight to [CinematicCompleteEvent] — see
/// `CinematicStep.skip` for what "skip" means per-step.
class CinematicSystem implements System {
  final List<CinematicStep> steps;
  int _index = 0;
  bool _started = false;
  bool _done = false;

  CinematicSystem(this.steps);

  @override
  String get name => 'cinematic';

  /// `false` once every step has completed or `skip` was called —
  /// check this (not `System` removal) to know when normal gameplay
  /// input should resume.
  bool get isPlaying => !_done;

  @override
  void update(World world, double dt) {
    if (_done) return;
    if (steps.isEmpty) {
      _complete(world);
      return;
    }
    if (!_started) {
      steps[_index].start(world);
      _started = true;
    }
    if (steps[_index].update(world, dt)) {
      _advance(world);
    }
  }

  void _advance(World world) {
    _index++;
    _started = false;
    if (_index >= steps.length) {
      _complete(world);
    } else {
      steps[_index].start(world);
      _started = true;
    }
  }

  /// Jumps straight to [CinematicCompleteEvent]: calls `skip` on the
  /// current step and every step still to come, in order, then
  /// completes. A no-op if already done.
  void skip(World world) {
    if (_done) return;
    for (var i = _index; i < steps.length; i++) {
      if (i == _index && !_started) steps[i].start(world);
      steps[i].skip(world);
    }
    _complete(world);
  }

  void _complete(World world) {
    if (_done) return;
    _done = true;
    world.events.emit(const CinematicCompleteEvent());
  }
}
