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
