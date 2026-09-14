// CinematicStep implementations that drive a Camera or a full-screen
// ScreenTint -- the pieces CinematicSystem itself deliberately doesn't
// know about (see its doc comment: "the engine only owns sequencing
// here, never what a cinematic actually does"). These live in
// engine_flutter, not engine_core alongside CinematicStep itself,
// because Camera is a rendering concern with no ECS/World presence
// (see Camera's own doc comment) -- a step needs a direct reference to
// the Camera instance EngineView is actually using, not something it
// can look up from World.
//
// A Scene using any of these should leave cameraFollowEntity at its
// default null (or otherwise not set the scene's camera to follow
// anything) -- EngineView hard-snaps Camera.x/.y to the followed
// entity's Position *every* tick when that's set, which would
// immediately undo whatever a CameraPanStep/CameraZoomStep/
// CameraFollowStep just did that same tick.

import 'package:engine_core/engine_core.dart';

import '../rendering/camera.dart';
import '../rendering/screen_tint.dart';

/// Pans `camera.x`/`.y` from wherever it currently is to ([toX], [toY])
/// over [duration] seconds, eased per [easing]. The *from* position is
/// captured in [start] (whatever the camera's actual position is the
/// moment this step becomes active), not passed in — so pans chain
/// naturally one after another without needing to track the previous
/// step's endpoint by hand.
class CameraPanStep extends CinematicStep {
  final Camera camera;
  final double toX;
  final double toY;
  final double duration;
  final EasingType easing;
  late final Tween _tweenX;
  late final Tween _tweenY;

  CameraPanStep(
    this.camera, {
    required this.toX,
    required this.toY,
    required this.duration,
    this.easing = EasingType.easeInOutQuad,
  });

  @override
  void start(World world) {
    _tweenX = Tween(from: camera.x, to: toX, duration: duration, easing: easing);
    _tweenY = Tween(from: camera.y, to: toY, duration: duration, easing: easing);
  }

  @override
  bool update(World world, double dt) {
    _tweenX.elapsed += dt;
    _tweenY.elapsed += dt;
    camera.x = _tweenX.value;
    camera.y = _tweenY.value;
    return _tweenX.isComplete;
  }

  @override
  void skip(World world) {
    camera.x = toX;
    camera.y = toY;
  }
}

/// Animates `camera.zoom` from its current value to [toZoom] over
/// [duration] seconds, eased per [easing] — a slow push-in on a boss
/// reveal, a pull-back at a level's end. Same "captures the *from*
/// value in `start`" reasoning as `CameraPanStep`.
class CameraZoomStep extends CinematicStep {
  final Camera camera;
  final double toZoom;
  final double duration;
  final EasingType easing;
  late final Tween _tween;

  CameraZoomStep(
    this.camera, {
    required this.toZoom,
    required this.duration,
    this.easing = EasingType.easeInOutQuad,
  });

  @override
  void start(World world) {
    _tween = Tween(from: camera.zoom, to: toZoom, duration: duration, easing: easing);
  }

  @override
  bool update(World world, double dt) {
    _tween.elapsed += dt;
    camera.zoom = _tween.value;
    return _tween.isComplete;
  }

  @override
  void skip(World world) => camera.zoom = toZoom;
}

/// Triggers `camera.shake(magnitude, duration)` once, then waits out
/// [duration] before letting the cinematic move on — the shake itself
/// decays via `Camera.update`, which `EngineView` already calls every
/// frame regardless, so this step's only job is to fire it and hold
/// the sequence until it's done rather than racing ahead.
class CameraShakeStep extends CinematicStep {
  final Camera camera;
  final double magnitude;
  final double duration;
  double _elapsed = 0;

  CameraShakeStep(this.camera, {required this.magnitude, required this.duration});

  @override
  void start(World world) {
    camera.shake(magnitude, duration);
    _elapsed = 0;
  }

  @override
  bool update(World world, double dt) {
    _elapsed += dt;
    return _elapsed >= duration;
  }

  @override
  void skip(World world) {
    // Nothing to force here -- Camera.shake's own decay already
    // reaches 0 offset on its own; skipping just stops this step from
    // holding up the rest of the cinematic while it plays out.
  }
}

/// Continuously re-centers the camera on [target]'s `Position` for
/// [duration] seconds — for tracking something that moves *during* a
/// cinematic beat (a thrown object, a fleeing enemy) rather than
/// following a fixed player character for an entire scene (that's
/// `Scene.cameraFollowEntity`'s job, not a cinematic step's).
///
/// [smoothing] is a `0`–`1` per-tick blend factor toward the target's
/// position — `1.0` (default) hard-snaps every tick, identical to
/// `Camera.follow`'s own behavior; a lower value trails behind with a
/// lag proportional to how small it is, for a softer "camera catching
/// up" feel instead of rigidly locking on.
class CameraFollowStep extends CinematicStep {
  final Camera camera;
  final EntityId target;
  final double duration;
  final double smoothing;
  double _elapsed = 0;

  CameraFollowStep(
    this.camera,
    this.target, {
    required this.duration,
    this.smoothing = 1.0,
  });

  @override
  bool update(World world, double dt) {
    _elapsed += dt;
    final pos = world.storeOf<Position>().get(target);
    if (pos != null) {
      if (smoothing >= 1.0) {
        camera.x = pos.x;
        camera.y = pos.y;
      } else {
        camera.x += (pos.x - camera.x) * smoothing;
        camera.y += (pos.y - camera.y) * smoothing;
      }
    }
    return _elapsed >= duration;
  }

  @override
  void skip(World world) {
    final pos = world.storeOf<Position>().get(target);
    if (pos != null) {
      camera.x = pos.x;
      camera.y = pos.y;
    }
  }
}

/// Fades a full-screen `ScreenTint` from [fromAlpha] to [toAlpha] (both
/// `0`–`1`) over [duration] seconds — fade-to-black between rooms
/// (`ScreenTintStep(colorArgb: 0xFF000000, fromAlpha: 0, toAlpha: 1,
/// ...)`), a sustained color grade for a cutscene's mood, or one half
/// of a flash (see [entity] below for the other half).
/// [colorArgb]'s own alpha channel is ignored — [fromAlpha]/[toAlpha]
/// are what's actually animated; only the RGB portion of [colorArgb]
/// is used as the tint's hue.
///
/// Spawns its own entity on [start] (or on [skip], if the cinematic is
/// skipped before this step ever starts) if [entity] isn't already set
/// — reads back as [entity] afterward either way, so a later step can
/// pick it up. **A quick flash (up fast, back down slower) needs two
/// `ScreenTintStep`s to *share one entity*** — pass the same `EntityId`
/// (from the first step's `.entity` once it's spawned one, or one you
/// `world.spawn()` yourself up front) as the second step's `entity`.
/// Without that, each step spawns its own separate entity, and the
/// first one's `ScreenTint` is left stuck at [toAlpha] forever once
/// its own step completes — nothing ever fades *that* entity back
/// down, since the second step is animating a different one entirely.
/// A lone fade (no second step reversing it) is exactly the case where
/// leaving [entity] unset and letting this step own a fresh one is
/// correct — e.g. a fade-to-black step's whole point is usually to
/// *stay* opaque past its own completion, until something else (a
/// scene change, another `ScreenTintStep` sharing its entity) says
/// otherwise.
class ScreenTintStep extends CinematicStep {
  final int colorArgb;
  final double fromAlpha;
  final double toAlpha;
  final double duration;
  final EasingType easing;

  /// The `ScreenTint` entity this step animates — pass one in (e.g.
  /// from an earlier `ScreenTintStep` you want this one to continue
  /// animating) to share it instead of spawning a new one; read back
  /// afterward to hand to a *later* step either way.
  EntityId? entity;

  late final Tween _tween;

  ScreenTintStep({
    required this.colorArgb,
    required this.fromAlpha,
    required this.toAlpha,
    required this.duration,
    this.easing = EasingType.linear,
    this.entity,
  });

  @override
  void start(World world) {
    entity ??= world.spawn();
    _tween = Tween(from: fromAlpha, to: toAlpha, duration: duration, easing: easing);
    world.storeOf<ScreenTint>().set(entity!, ScreenTint(_withAlpha(colorArgb, fromAlpha)));
  }

  @override
  bool update(World world, double dt) {
    _tween.elapsed += dt;
    world.storeOf<ScreenTint>().get(entity!)?.colorArgb = _withAlpha(colorArgb, _tween.value);
    return _tween.isComplete;
  }

  @override
  void skip(World world) {
    if (entity == null) start(world);
    world.storeOf<ScreenTint>().get(entity!)?.colorArgb = _withAlpha(colorArgb, toAlpha);
  }

  static int _withAlpha(int colorArgb, double alpha) {
    final a = (alpha.clamp(0.0, 1.0) * 255).round();
    return (a << 24) | (colorArgb & 0x00FFFFFF);
  }
}
