/// A named sequence of atlas regions played at a fixed frame duration.
/// Pure data (list of strings + numbers) so an agent can define new
/// animations without touching Dart.
class AnimationClip {
  final String name;
  final List<String> frameRegions;
  final double frameDurationSeconds;
  final bool loop;

  AnimationClip(
    this.name,
    this.frameRegions, {
    this.frameDurationSeconds = 0.1,
    this.loop = true,
  });

  /// Builds a clip from a naming convention (`${prefix}_0`, `${prefix}_1`,
  /// ...) instead of spelling out `List.generate(n, (i) => 'walk_\$i')`
  /// at every call site — the common case for a sprite sheet where
  /// frames are already laid out and named that way.
  factory AnimationClip.sequence(
    String name,
    String prefix,
    int frameCount, {
    double frameDurationSeconds = 0.1,
    bool loop = true,
  }) =>
      AnimationClip(
        name,
        List.generate(frameCount, (i) => '${prefix}_$i'),
        frameDurationSeconds: frameDurationSeconds,
        loop: loop,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'frameRegions': frameRegions,
        'frameDurationSeconds': frameDurationSeconds,
        'loop': loop,
      };

  factory AnimationClip.fromJson(Map<String, dynamic> json) => AnimationClip(
        json['name'] as String,
        (json['frameRegions'] as List).cast<String>(),
        frameDurationSeconds:
            (json['frameDurationSeconds'] as num?)?.toDouble() ?? 0.1,
        loop: json['loop'] as bool? ?? true,
      );
}

/// Playback state for one entity's currently-playing clip. `AnimationSystem`
/// advances `elapsed`/`frameIndex` each tick and writes the resulting
/// region name onto the entity's `Sprite` component.
///
/// [crossfadeSeconds] (`0` default — disabled, an instant cut exactly
/// like before this field existed) tells whatever system swaps [clip]
/// (e.g. `MovementAnimationSystem`) to snapshot the outgoing frame into
/// an `AnimationTransition` first, so the old frame fades out over
/// this many seconds instead of popping away the instant the new clip
/// takes over.
class AnimationState {
  AnimationClip clip;
  int frameIndex;
  double elapsed;
  bool playing;
  double crossfadeSeconds;

  AnimationState(
    this.clip, {
    this.frameIndex = 0,
    this.elapsed = 0,
    this.playing = true,
    this.crossfadeSeconds = 0,
  });

  Map<String, dynamic> toJson() => {
        'clip': clip.toJson(),
        'frameIndex': frameIndex,
        'elapsed': elapsed,
        'playing': playing,
        'crossfadeSeconds': crossfadeSeconds,
      };

  factory AnimationState.fromJson(Map<String, dynamic> json) => AnimationState(
        AnimationClip.fromJson(json['clip'] as Map<String, dynamic>),
        frameIndex: json['frameIndex'] as int? ?? 0,
        elapsed: (json['elapsed'] as num?)?.toDouble() ?? 0,
        playing: json['playing'] as bool? ?? true,
        crossfadeSeconds: (json['crossfadeSeconds'] as num?)?.toDouble() ?? 0,
      );
}
