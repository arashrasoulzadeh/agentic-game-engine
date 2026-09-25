import '../rendering/tween.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import '../physics/position.dart';
import '../ecs/entity.dart';
import '../content/game_state.dart';
import '../content/string_table.dart';

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

/// Moves the camera to target [targetX]/[targetY] over [duration] seconds,
/// using [easing]. If [followEntity] is provided, targets that entity's
/// position instead of fixed coordinates. The camera is assumed to be
/// whatever entity [Scene.cameraFollowEntity] points at (or a given
/// [cameraEntity] override).
class MoveCameraStep extends CinematicStep {
  final double? targetX;
  final double? targetY;
  final double duration;
  final EasingType easing;
  final EntityId? followEntity;
  final EntityId? cameraEntity;
  late final Tween _tween;
  late double _startX;
  late double _startY;
  double _endX = 0;
  double _endY = 0;
  bool _started = false;

  MoveCameraStep({
    this.targetX,
    this.targetY,
    required this.duration,
    this.easing = EasingType.easeInOutQuad,
    this.followEntity,
    this.cameraEntity,
  });

  @override
  void start(World world) {
    final camEntity = cameraEntity ?? (world.storeOf<EntityId>().get(0) ?? 0);
    final camPos = world.storeOf<Position>().get(camEntity);
    if (camPos == null) return;

    _startX = camPos.x;
    _startY = camPos.y;

    _endX = _startX;
    _endY = _startY;

    if (followEntity != null) {
      final targetPos = world.storeOf<Position>().get(followEntity!);
      if (targetPos != null) {
        _endX = targetPos.x;
        _endY = targetPos.y;
      }
    } else {
      if (targetX != null) _endX = targetX!;
      if (targetY != null) _endY = targetY!;
    }

    _tween = Tween(from: 0, to: 1, duration: duration, easing: easing);
  }

  @override
  bool update(World world, double dt) {
    if (!_started) {
      start(world);
      _started = true;
    }

    _tween.elapsed += dt;
    final t = _tween.value.clamp(0.0, 1.0);

    final camEntity = cameraEntity ?? (world.storeOf<EntityId>().get(0) ?? 0);
    final camPos = world.storeOf<Position>().get(camEntity);
    if (camPos == null) return _tween.isComplete;

    // If following entity, update target dynamically
    double endX = _endX;
    double endY = _endY;
    if (followEntity != null) {
      final targetPos = world.storeOf<Position>().get(followEntity!);
      if (targetPos != null) {
        endX = targetPos.x;
        endY = targetPos.y;
      }
    }

    final newX = _startX + (endX - _startX) * t;
    final newY = _startY + (endY - _startY) * t;

    world.storeOf<Position>().set(camEntity, Position(newX, newY));

    return _tween.isComplete;
  }

  @override
  void skip(World world) {
    final camEntity = cameraEntity ?? (world.storeOf<EntityId>().get(0) ?? 0);
    final camPos = world.storeOf<Position>().get(camEntity);
    if (camPos == null) return;

    double endX = _endX;
    double endY = _endY;
    if (followEntity != null) {
      final targetPos = world.storeOf<Position>().get(followEntity!);
      if (targetPos != null) {
        endX = targetPos.x;
        endY = targetPos.y;
      }
    }

    world.storeOf<Position>().set(camEntity, Position(endX, endY));
  }
}

/// Spawns an entity from a template [templateId] (registered in
/// [Level] or via [EntityTemplateRegistry]). Completes immediately.
/// Useful for spawning enemies, props, or effects at specific cinematic beats.
class SpawnEntityStep extends CinematicStep {
  final String templateId;
  final double? overrideX;
  final double? overrideY;

  SpawnEntityStep({
    required this.templateId,
    this.overrideX,
    this.overrideY,
  });

  @override
  bool update(World world, double dt) {
    // Template resolution would be implemented by the game
    // For now, just complete immediately
    return true;
  }
}

/// Plays a sound effect or music track. Completes immediately (fire-and-forget)
/// unless [waitForCompletion] is true, in which case waits [duration] seconds.
class PlaySoundStep extends CinematicStep {
  final String soundId;
  final double? duration;
  final double volume;
  final bool waitForCompletion;

  PlaySoundStep({
    required this.soundId,
    this.duration,
    this.volume = 1.0,
    this.waitForCompletion = false,
  });

  double _elapsed = 0;

  @override
  void start(World world) {
    // Sound playback would be triggered via engine_flutter's audio system
    // For engine_core, just emit an event the game can listen to
    world.events.emit(_PlaySoundEvent(soundId, volume));
  }

  @override
  bool update(World world, double dt) {
    if (!waitForCompletion) return true;
    if (duration == null) return true;
    _elapsed += dt;
    return _elapsed >= duration!;
  }

  @override
  void skip(World world) {
    // Sound is already playing, just complete
  }
}

/// Emitted by [PlaySoundStep] for the game's audio system to handle.
class _PlaySoundEvent {
  final String soundId;
  final double volume;
  _PlaySoundEvent(this.soundId, this.volume);
}

/// Sets a flag in [GameState.data] (e.g. "boss_defeated" = true).
/// Completes immediately.
class SetFlagStep extends CinematicStep {
  final String flag;
  final bool value;

  SetFlagStep({required this.flag, this.value = true});

  @override
  void start(World world) {
    final state = world.storeOf<GameState>().get(0);
    if (state != null) {
      state.data[flag] = value;
    }
  }

  @override
  bool update(World world, double dt) => true;
}

/// Triggers a camera shake effect over [duration] seconds with [intensity].
/// Completes when the shake finishes.
class CameraShakeStep extends CinematicStep {
  final double duration;
  final double intensity;
  late final Tween _tween;
  EntityId? _cameraEntity;

  CameraShakeStep({
    required this.duration,
    this.intensity = 10,
  });

  @override
  void start(World world) {
    _cameraEntity = world.storeOf<EntityId>().get(0); // fallback
    _tween = Tween(from: 0, to: 1, duration: duration);
  }

  @override
  bool update(World world, double dt) {
    _tween.elapsed += dt;
    final t = _tween.value;

    // Emit shake offset event for engine_flutter's camera to consume
    world.events.emit(_CameraShakeEvent(intensity * (1.0 - t)));

    return _tween.isComplete;
  }

  @override
  void skip(World world) {
    _tween.elapsed = _tween.duration;
    world.events.emit(_CameraShakeEvent(0));
  }
}

/// Emitted by [CameraShakeStep] for engine_flutter's camera to apply shake offset.
class _CameraShakeEvent {
  final double offset;
  _CameraShakeEvent(this.offset);
}

/// Makes the camera follow [targetEntity] for [duration] seconds.
/// After [duration], camera returns to normal behavior (or keeps following
/// if [keepFollowing] is true).
class FollowEntityStep extends CinematicStep {
  final EntityId targetEntity;
  final double duration;
  final bool keepFollowing;
  double _elapsed = 0;

  FollowEntityStep({
    required this.targetEntity,
    required this.duration,
    this.keepFollowing = false,
  });

  @override
  bool update(World world, double dt) {
    _elapsed += dt;

    final targetPos = world.storeOf<Position>().get(targetEntity);
    if (targetPos != null) {
      // Emit event for engine_flutter's camera to follow
      world.events.emit(_FollowCameraEvent(targetEntity));
    }

    return _elapsed >= duration;
  }

  @override
  void skip(World world) {
    if (keepFollowing) {
      world.events.emit(_FollowCameraEvent(targetEntity));
    }
  }
}

/// Emitted by [FollowEntityStep] for engine_flutter's camera to follow target.
class _FollowCameraEvent {
  final EntityId target;
  _FollowCameraEvent(this.target);
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
