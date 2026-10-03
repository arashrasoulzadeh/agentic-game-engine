import 'package:engine_core/engine_core.dart';

import '../rendering/clip_shape.dart';
import '../rendering/screen_tint.dart';

/// The type of transition effect to apply when switching scenes.
enum SceneTransitionType {
  /// Fade to/from a solid color (default black).
  fade,

  /// Iris/wipe effect — a growing/shrinking circle reveals the new scene.
  iris,
}

/// Configuration for a scene transition's look — not its direction.
/// `GameRunner.loadSceneWithTransition` always plays a transition as two
/// phases sharing this same config (cover the outgoing scene, swap,
/// reveal the incoming one) — see [SceneTransition.covering] for where
/// the direction for each phase actually comes from.
class SceneTransitionConfig {
  /// The type of transition effect.
  final SceneTransitionType type;

  /// Duration of *each* phase, in seconds — a full
  /// `loadSceneWithTransition` call takes `2 * duration` wall-clock time
  /// (cover, then reveal).
  final double duration;

  /// Easing curve for the transition progress.
  final EasingType easing;

  /// For fade transitions: the color to fade to/from (ARGB).
  /// Defaults to black (0xFF000000).
  final int fadeColorArgb;

  const SceneTransitionConfig({
    this.type = SceneTransitionType.fade,
    this.duration = 0.5,
    this.easing = EasingType.easeInOutQuad,
    this.fadeColorArgb = 0xFF000000,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'duration': duration,
        'easing': easing.name,
        'fadeColorArgb': fadeColorArgb,
      };

  factory SceneTransitionConfig.fromJson(Map<String, dynamic> json) =>
      SceneTransitionConfig(
        type: SceneTransitionType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => SceneTransitionType.fade,
        ),
        duration: (json['duration'] as num?)?.toDouble() ?? 0.5,
        easing: EasingType.values.firstWhere(
          (e) => e.name == json['easing'],
          orElse: () => EasingType.easeInOutQuad,
        ),
        fadeColorArgb: (json['fadeColorArgb'] as num?)?.toInt() ?? 0xFF000000,
      );
}

/// Component attached to an entity that manages a scene transition.
/// When active, this component drives the transition animation.
/// The actual visual effect is rendered by EngineView via ScreenTint
/// (for fade) or ClipShape (for iris) components that this component
/// creates and updates.
class SceneTransition {
  /// The transition configuration.
  final SceneTransitionConfig config;

  /// `true`: this phase plays from fully visible to fully covered (the
  /// "outgoing scene" half of a transition, played right before the
  /// scene swap). `false`: fully covered to fully visible (the
  /// "incoming scene" half, played right after). A single
  /// [SceneTransitionConfig] has no notion of direction by itself —
  /// `GameRunner` plays the same config twice, once with each value,
  /// to cover then reveal across a scene swap.
  final bool covering;

  /// Current progress of the transition (0.0 to 1.0).
  double progress = 0.0;

  /// Whether the transition is currently running.
  bool isRunning = false;

  /// Whether the transition has completed.
  bool isComplete = false;

  /// Internal tween for the transition progress.
  Tween? _tween;

  /// The entity IDs for the transition effect components.
  EntityId? _screenTintEntity;
  EntityId? _clipShapeEntity;

  SceneTransition({
    required this.config,
    required this.covering,
  });

  /// Starts the transition by creating the necessary effect components.
  /// [cameraX] and [cameraY] are the camera's world position, used to center
  /// the iris transition on the screen.
  void start(World world, {double cameraX = 0, double cameraY = 0}) {
    isRunning = true;
    isComplete = false;
    progress = 0.0;

    _tween = Tween(
      from: 0.0,
      to: 1.0,
      duration: config.duration,
      easing: config.easing,
    );

    // Create effect components based on transition type, seeded at this
    // phase's starting value (see [update]'s mirrored end value) so the
    // very first frame doesn't flash the *other* phase's state for one
    // tick before [update] first runs.
    switch (config.type) {
      case SceneTransitionType.fade:
        _screenTintEntity = world.spawn();
        final startColor =
            (config.fadeColorArgb & 0x00FFFFFF) | ((covering ? 0 : 255) << 24);
        world.storeOf<ScreenTint>().set(_screenTintEntity!, ScreenTint(startColor));
        break;
      case SceneTransitionType.iris:
        _clipShapeEntity = world.spawn();
        world.storeOf<Position>().set(_clipShapeEntity!, Position(cameraX, cameraY));
        world.storeOf<ClipShape>().set(_clipShapeEntity!, ClipShape(
          isCircle: true,
          radius: covering ? _maxRadius(world) : 0,
          mode: ClipShapeMode.reveal,
          softness: 0,
        ));
        break;
    }
  }

  double _maxRadius(World world) {
    final viewportWidth = world.width.toDouble();
    final viewportHeight = world.height.toDouble();
    return (viewportWidth > viewportHeight ? viewportWidth : viewportHeight) * 1.5;
  }

  /// Advances the transition by [dt] seconds. Returns true if complete.
  bool update(double dt, World world) {
    if (!isRunning || _tween == null) return true;

    _tween!.elapsed += dt;
    progress = _tween!.value;
    isComplete = _tween!.isComplete;

    // Update effect components. [covering] plays 0->1 as visible->hidden;
    // the reveal phase is the same animation mirrored (1-progress), not
    // a second code path, since both ends are the same shapes/colors.
    final coverAmount = covering ? progress : 1 - progress;
    switch (config.type) {
      case SceneTransitionType.fade:
        if (_screenTintEntity != null) {
          final alpha = (coverAmount * 255).round().clamp(0, 255);
          final color = (config.fadeColorArgb & 0x00FFFFFF) | (alpha << 24);
          world.storeOf<ScreenTint>().get(_screenTintEntity!)?.colorArgb = color;
        }
        break;
      case SceneTransitionType.iris:
        if (_clipShapeEntity != null) {
          final radius = _maxRadius(world) * (1 - coverAmount);
          world.storeOf<ClipShape>().get(_clipShapeEntity!)?.radius = radius;
        }
        break;
    }

    if (isComplete) {
      isRunning = false;
      // Clean up effect components
      if (_screenTintEntity != null) {
        world.destroy(_screenTintEntity!);
        _screenTintEntity = null;
      }
      if (_clipShapeEntity != null) {
        world.destroy(_clipShapeEntity!);
        _clipShapeEntity = null;
      }
    }
    return isComplete;
  }

  /// Gets the current transition progress with easing applied (0.0 to 1.0).
  double get easedProgress => progress;

  Map<String, dynamic> toJson() => {
        'config': config.toJson(),
        'covering': covering,
        'progress': progress,
        'isRunning': isRunning,
        'isComplete': isComplete,
      };

  factory SceneTransition.fromJson(Map<String, dynamic> json) {
    final config = SceneTransitionConfig.fromJson(json['config'] as Map<String, dynamic>);
    final transition = SceneTransition(
      config: config,
      covering: json['covering'] as bool? ?? true,
    );
    transition.progress = (json['progress'] as num?)?.toDouble() ?? 0.0;
    transition.isRunning = json['isRunning'] as bool? ?? false;
    transition.isComplete = json['isComplete'] as bool? ?? false;
    return transition;
  }
}

/// A system that updates active scene transitions.
class SceneTransitionSystem implements System {
  @override
  String get name => 'SceneTransitionSystem';

  @override
  void update(World world, double dt) {
    final transitions = world.storeOf<SceneTransition>();
    for (var i = 0; i < transitions.length; i++) {
      final transition = transitions.denseAt(i);
      if (transition.isRunning) {
        transition.update(dt, world);
      }
    }
  }
}