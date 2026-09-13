/// A transient "ghost" of the frame an entity's `Sprite` was showing
/// right before its `AnimationState.clip` changed — drawn fading out
/// at the same `Position` while the entity's real `Sprite` shows the
/// new clip's frame, for a crossfade instead of an instant pop.
/// Frozen-frame, not fully animated: the outgoing clip doesn't keep
/// advancing during the fade, it's the one frame it was on at the
/// moment of the swap, fading to transparent — a deliberate
/// simplification over blending two fully-live animations, which
/// would need a second complete playback state (frame index, elapsed
/// time, looping) rather than one snapshot.
///
/// Written by `MovementAnimationSystem` (or any code driving
/// `AnimationState.clip` that wants this) the tick a clip actually
/// changes, on an entity whose `AnimationState.crossfadeSeconds > 0`.
/// Counted down and removed by `AnimationTransitionSystem` once
/// `remainingSeconds` reaches `0`. Not meant to be created directly
/// from game code in the common case — set `crossfadeSeconds` on
/// `AnimationState` instead and let the animation-driving system
/// manage this.
class AnimationTransition {
  String atlasId;
  String region;
  double scaleX;
  double scaleY;
  double rotation;
  int zIndex;
  double remainingSeconds;
  double totalSeconds;

  AnimationTransition(
    this.atlasId,
    this.region, {
    this.scaleX = 1,
    this.scaleY = 1,
    this.rotation = 0,
    this.zIndex = 0,
    required this.remainingSeconds,
    required this.totalSeconds,
  });

  /// Fade progress, `1` (fully opaque) at the moment of the swap down
  /// to `0` (invisible) as `remainingSeconds` runs out. `totalSeconds
  /// <= 0` reads as already-finished rather than dividing by zero.
  double get alpha => totalSeconds <= 0 ? 0 : (remainingSeconds / totalSeconds).clamp(0, 1);

  Map<String, dynamic> toJson() => {
        'atlasId': atlasId,
        'region': region,
        'scaleX': scaleX,
        'scaleY': scaleY,
        'rotation': rotation,
        'zIndex': zIndex,
        'remainingSeconds': remainingSeconds,
        'totalSeconds': totalSeconds,
      };

  factory AnimationTransition.fromJson(Map<String, dynamic> json) => AnimationTransition(
        json['atlasId'] as String,
        json['region'] as String,
        scaleX: (json['scaleX'] as num?)?.toDouble() ?? 1,
        scaleY: (json['scaleY'] as num?)?.toDouble() ?? 1,
        rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
        zIndex: (json['zIndex'] as num?)?.toInt() ?? 0,
        remainingSeconds: (json['remainingSeconds'] as num).toDouble(),
        totalSeconds: (json['totalSeconds'] as num).toDouble(),
      );
}
