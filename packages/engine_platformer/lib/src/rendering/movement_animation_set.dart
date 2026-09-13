import 'package:engine_flutter/engine_flutter.dart';

/// Names which `AnimationClip` to play for idle/walking/airborne —
/// `MovementAnimationSystem` reads this each tick and swaps the
/// entity's `AnimationState` clip when the movement state changes, so a
/// game doesn't have to hand-write "if moving play walk else idle"
/// logic per character.
class MovementAnimationSet {
  final AnimationClip idle;
  final AnimationClip walk;

  /// Played while airborne (not `grounded`, per `PlatformerController`),
  /// if provided. Falls back to [walk]/[idle] when null.
  final AnimationClip? jump;

  /// Horizontal speed above which the entity counts as "walking" rather
  /// than "idle".
  final double moveThreshold;

  MovementAnimationSet({
    required this.idle,
    required this.walk,
    this.jump,
    this.moveThreshold = 5,
  });

  /// Builds idle/walk/jump clips from atlas region names in one call —
  /// the common case for a sprite sheet with a single idle frame and
  /// numbered walk/jump sequences (`walk_0`, `walk_1`, ... — see
  /// `AnimationClip.sequence`), instead of constructing each `AnimationClip`
  /// by hand. [idleRegion] is a single frame name since idle poses are
  /// usually static; [walkPrefix]/[jumpPrefix] follow the `${prefix}_N`
  /// numbering convention.
  factory MovementAnimationSet.fromSequences({
    required String idleRegion,
    required String walkPrefix,
    required int walkFrameCount,
    String? jumpPrefix,
    int? jumpFrameCount,
    double idleFrameDurationSeconds = 0.2,
    double walkFrameDurationSeconds = 0.1,
    double jumpFrameDurationSeconds = 0.1,
    double moveThreshold = 5,
  }) {
    return MovementAnimationSet(
      idle: AnimationClip('idle', [idleRegion],
          frameDurationSeconds: idleFrameDurationSeconds),
      walk: AnimationClip.sequence('walk', walkPrefix, walkFrameCount,
          frameDurationSeconds: walkFrameDurationSeconds),
      jump: (jumpPrefix != null && jumpFrameCount != null)
          ? AnimationClip.sequence('jump', jumpPrefix, jumpFrameCount,
              frameDurationSeconds: jumpFrameDurationSeconds, loop: false)
          : null,
      moveThreshold: moveThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
        'idle': idle.toJson(),
        'walk': walk.toJson(),
        if (jump != null) 'jump': jump!.toJson(),
        'moveThreshold': moveThreshold,
      };

  factory MovementAnimationSet.fromJson(Map<String, dynamic> json) =>
      MovementAnimationSet(
        idle: AnimationClip.fromJson(json['idle'] as Map<String, dynamic>),
        walk: AnimationClip.fromJson(json['walk'] as Map<String, dynamic>),
        jump: json['jump'] == null
            ? null
            : AnimationClip.fromJson(json['jump'] as Map<String, dynamic>),
        moveThreshold: (json['moveThreshold'] as num?)?.toDouble() ?? 5,
      );
}
