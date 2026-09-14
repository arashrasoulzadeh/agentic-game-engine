import 'package:engine_flutter/engine_flutter.dart';

/// Breaks a jump into the distinct poses a real jump arc actually
/// passes through — crouch-and-launch, rising, the weightless instant
/// at the top, falling, absorbing the landing impact, and standing back
/// up — each its own `AnimationClip`, instead of `MovementAnimationSet`'s
/// single `jump` clip played on a fixed timer with no idea how high this
/// particular jump went or how long it takes to come back down. See
/// `JumpAnimationSystem`, which picks among these every tick from the
/// entity's actual `Velocity.y` and `PlatformerController.grounded`
/// transitions, not elapsed time.
///
/// Entirely opt-in: an entity with no `JumpAnimationSet` is untouched by
/// `JumpAnimationSystem`, and keeps using `MovementAnimationSet.jump` (or
/// falling back to idle/walk while airborne) exactly as before this
/// existed.
class JumpAnimationSet {
  /// The instant of leaving the ground — a crouch/launch pose. Shown
  /// for [startHoldSeconds] after liftoff before handing off to
  /// [rising], since real jump physics in this engine snaps
  /// `Velocity.y` to full speed the same tick `grounded` goes false
  /// (see `JumpSystem`) — there's no separate "charging up" tick to
  /// naturally show this pose during, so it's held briefly by a timer
  /// instead of picked by velocity like the rest of these are.
  final AnimationClip start;

  /// Shown while ascending (`Velocity.y` below `-peakVelocityThreshold`).
  final AnimationClip rising;

  /// Shown while airborne with `Velocity.y` within
  /// `±peakVelocityThreshold` of zero — real jump arcs pass through
  /// zero vertical speed for only an instant, so this dead zone is what
  /// actually gives the peak pose a moment on screen instead of a
  /// single skipped frame between [rising] and [falling].
  final AnimationClip peak;

  /// Shown while descending (`Velocity.y` above `peakVelocityThreshold`).
  final AnimationClip falling;

  /// Shown the instant `grounded` becomes true again after being
  /// airborne — the impact absorb, held for [landingHoldSeconds] before
  /// handing off to [completed].
  final AnimationClip landing;

  /// Shown for [completedHoldSeconds] right after [landing], before
  /// `JumpAnimationSystem` stops touching `AnimationState` at all and
  /// lets `MovementAnimationSystem`'s own idle/walk selection (which
  /// runs earlier the same tick) take back over.
  final AnimationClip completed;

  /// `Velocity.y` magnitude below which airborne motion counts as
  /// [peak] rather than still [rising]/[falling].
  final double peakVelocityThreshold;

  final double startHoldSeconds;
  final double landingHoldSeconds;
  final double completedHoldSeconds;

  /// `Velocity.x` magnitude above which the player actively trying to
  /// move cuts the [landing]/[completed] hold short instead of waiting
  /// it out — real player input should never feel locked out by a
  /// landing-recovery animation still playing. Reported live: without
  /// this, pressing a movement key right after touching down did
  /// nothing visible until the hold finished, reading as movement not
  /// working ("continues on floor... invalid") rather than as a
  /// deliberate recovery beat.
  final double moveInterruptThreshold;

  JumpAnimationSet({
    required this.start,
    required this.rising,
    required this.peak,
    required this.falling,
    required this.landing,
    required this.completed,
    this.peakVelocityThreshold = 40,
    this.startHoldSeconds = 0.08,
    this.landingHoldSeconds = 0.06,
    this.completedHoldSeconds = 0.08,
    this.moveInterruptThreshold = 5,
  });

  /// Builds every phase from atlas region names — the common case for a
  /// sheet with one row of jump-arc poses. Each list is that phase's
  /// `AnimationClip.frameRegions` directly (most phases just want one
  /// region, e.g. `['jump_0']`; [rising] can take more than one, e.g.
  /// `['jump_1', 'jump_2']`, to animate through the ascent instead of
  /// holding a single frame).
  factory JumpAnimationSet.fromRegions({
    required List<String> start,
    required List<String> rising,
    required List<String> peak,
    required List<String> falling,
    required List<String> landing,
    required List<String> completed,
    double peakVelocityThreshold = 40,
    double startHoldSeconds = 0.08,
    double landingHoldSeconds = 0.06,
    double completedHoldSeconds = 0.08,
    double moveInterruptThreshold = 5,
  }) =>
      JumpAnimationSet(
        start: AnimationClip('jumpStart', start, loop: false),
        rising: AnimationClip('jumpRising', rising, loop: true, frameDurationSeconds: 0.08),
        peak: AnimationClip('jumpPeak', peak, loop: false),
        falling: AnimationClip('jumpFalling', falling, loop: false),
        landing: AnimationClip('jumpLanding', landing, loop: false),
        completed: AnimationClip('jumpCompleted', completed, loop: false),
        peakVelocityThreshold: peakVelocityThreshold,
        startHoldSeconds: startHoldSeconds,
        landingHoldSeconds: landingHoldSeconds,
        completedHoldSeconds: completedHoldSeconds,
        moveInterruptThreshold: moveInterruptThreshold,
      );

  Map<String, dynamic> toJson() => {
        'start': start.toJson(),
        'rising': rising.toJson(),
        'peak': peak.toJson(),
        'falling': falling.toJson(),
        'landing': landing.toJson(),
        'completed': completed.toJson(),
        'peakVelocityThreshold': peakVelocityThreshold,
        'startHoldSeconds': startHoldSeconds,
        'landingHoldSeconds': landingHoldSeconds,
        'completedHoldSeconds': completedHoldSeconds,
        'moveInterruptThreshold': moveInterruptThreshold,
      };

  factory JumpAnimationSet.fromJson(Map<String, dynamic> json) => JumpAnimationSet(
        start: AnimationClip.fromJson(json['start'] as Map<String, dynamic>),
        rising: AnimationClip.fromJson(json['rising'] as Map<String, dynamic>),
        peak: AnimationClip.fromJson(json['peak'] as Map<String, dynamic>),
        falling: AnimationClip.fromJson(json['falling'] as Map<String, dynamic>),
        landing: AnimationClip.fromJson(json['landing'] as Map<String, dynamic>),
        completed: AnimationClip.fromJson(json['completed'] as Map<String, dynamic>),
        peakVelocityThreshold: (json['peakVelocityThreshold'] as num?)?.toDouble() ?? 40,
        startHoldSeconds: (json['startHoldSeconds'] as num?)?.toDouble() ?? 0.08,
        landingHoldSeconds: (json['landingHoldSeconds'] as num?)?.toDouble() ?? 0.06,
        completedHoldSeconds: (json['completedHoldSeconds'] as num?)?.toDouble() ?? 0.08,
        moveInterruptThreshold: (json['moveInterruptThreshold'] as num?)?.toDouble() ?? 5,
      );
}

/// Which `JumpAnimationSet` phase is currently showing (`'start'`,
/// `'rising'`, `'peak'`, `'falling'`, `'landing'`, `'completed'`, or
/// `null` for grounded/not-jumping), plus how long the entity has held
/// it — internal runtime bookkeeping `JumpAnimationSystem` owns, not
/// meant to be set from game code. A separate component from
/// `AnimationState` (rather than inferring the current phase from
/// `AnimationState.clip.name`) so `JumpAnimationSystem` doesn't have to
/// guess whether `MovementAnimationSystem`'s own write earlier the same
/// tick was its own or the phase it left behind last tick — this always
/// reflects exactly what `JumpAnimationSystem` itself last decided,
/// regardless of what anything else did to `AnimationState` in between.
class JumpAnimationPhaseState {
  String? phase;
  double elapsed;

  JumpAnimationPhaseState({this.phase, this.elapsed = 0});

  Map<String, dynamic> toJson() => {
        if (phase != null) 'phase': phase,
        'elapsed': elapsed,
      };

  factory JumpAnimationPhaseState.fromJson(Map<String, dynamic> json) =>
      JumpAnimationPhaseState(
        phase: json['phase'] as String?,
        elapsed: (json['elapsed'] as num?)?.toDouble() ?? 0,
      );
}
