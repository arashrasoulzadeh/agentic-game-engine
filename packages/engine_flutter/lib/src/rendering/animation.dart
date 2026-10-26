import 'package:engine_core/engine_core.dart';

/// A named sequence of atlas regions played at a fixed frame duration.
/// Pure data (list of strings + numbers) so an agent can define new
/// animations without touching Dart.
///
/// [frameOffsetsY] (and [frameOffsetsX]) are optional, per-frame pixel
/// offsets — in the same unscaled units as the atlas region's own
/// width/height — added to `Sprite.offsetX`/`offsetY` (see its own doc
/// comment) each time `AnimationSystem` advances to that frame. `null`
/// (the default) is unchanged behavior: every frame draws centered on
/// `Position`, exactly as before these existed.
///
/// The gap they fill: a hand-painted sprite sheet frequently has
/// frames of genuinely different pixel heights across one character
/// (a windup pose reaches higher, a crouch is shorter, a death
/// collapse shrinks frame by frame) — tightly cropped so the atlas
/// wastes no space per frame, which is exactly what makes each frame's
/// *center* a different distance from the character's actual feet.
/// Center-anchoring (the engine's only option before this) then makes
/// the character visibly bob up and down as its animation switches
/// between clips of different average frame height — confirmed live
/// with a real sheet: idle's frames run ~220px tall, several walk
/// frames only ~200px, and the character floated a few pixels above
/// the ground the instant it started walking. `frameOffsetsY[i]` lets
/// content authors counteract that per frame: computed once as
/// `referenceHalfHeight - frameHeight[i] / 2` against whichever clip's
/// height is treated as the character's "true" standing height, it
/// pushes every other frame down (or up) by exactly the amount needed
/// to keep the character's feet at a constant screen position
/// regardless of which frame is currently showing.
///
/// When present, must be the same length as [frameRegions] — indexed
/// identically, i.e. `frameOffsetsY[i]` applies while `frameRegions[i]`
/// is showing.
///
/// [frameEvents] is the same optional per-frame list pattern: when
/// playback *enters* frame `i`, `AnimationSystem` emits one
/// [AnimationFrameEvent] per entry in `frameEvents[i]` (empty lists are
/// fine). Types are opaque strings (`sfx`, `hitbox_on`, …) so genre /
/// game code can subscribe without baking meaning into the animator.
class AnimationClip {
  final String name;
  final List<String> frameRegions;
  final double frameDurationSeconds;
  final bool loop;
  final List<double>? frameOffsetsX;
  final List<double>? frameOffsetsY;
  final List<List<AnimationEvent>>? frameEvents;

  AnimationClip(
    this.name,
    this.frameRegions, {
    this.frameDurationSeconds = 0.1,
    this.loop = true,
    this.frameOffsetsX,
    this.frameOffsetsY,
    this.frameEvents,
  }) : assert(
         frameOffsetsX == null || frameOffsetsX.length == frameRegions.length,
         'frameOffsetsX must have one entry per frameRegions entry',
       ),
       assert(
         frameOffsetsY == null || frameOffsetsY.length == frameRegions.length,
         'frameOffsetsY must have one entry per frameRegions entry',
       ),
       assert(
         frameEvents == null || frameEvents.length == frameRegions.length,
         'frameEvents must have one entry per frameRegions entry',
       );

  /// Builds a clip from a naming convention (`${prefix}_0`, `${prefix}_1`,
  /// ...) instead of spelling out `List.generate(n, (i) => 'walk_$i')`
  /// at every call site — the common case for a sprite sheet where
  /// frames are already laid out and named that way.
  ///
  /// Memoized by its full argument set: a call site that (re)builds the
  /// same sequence repeatedly — e.g. from inside `Scene.populate`,
  /// which reruns on every scene reload/room transition, not just once
  /// at startup — gets back the exact same instance instead of
  /// re-running `List.generate`/re-allocating a fresh `List<String>`
  /// and `AnimationClip` every time. Safe to share: every field here is
  /// `final` and nothing in this engine mutates a clip's
  /// `frameRegions` list in place once built (`AnimationSystem` and
  /// friends only ever read it or swap out the whole `AnimationClip`,
  /// never mutate one's fields) — see [AnimationClip]'s own "pure data"
  /// framing.
  factory AnimationClip.sequence(
    String name,
    String prefix,
    int frameCount, {
    double frameDurationSeconds = 0.1,
    bool loop = true,
    List<double>? frameOffsetsX,
    List<double>? frameOffsetsY,
    List<List<AnimationEvent>>? frameEvents,
  }) {
    final key =
        '$name$prefix$frameCount$frameDurationSeconds$loop'
        '${frameOffsetsX ?? ''}${frameOffsetsY ?? ''}${frameEvents ?? ''}';
    return _sequenceCache.putIfAbsent(
      key,
      () => AnimationClip(
        name,
        List.generate(frameCount, (i) => '${prefix}_$i'),
        frameDurationSeconds: frameDurationSeconds,
        loop: loop,
        frameOffsetsX: frameOffsetsX,
        frameOffsetsY: frameOffsetsY,
        frameEvents: frameEvents,
      ),
    );
  }

  static final Map<String, AnimationClip> _sequenceCache = {};

  Map<String, dynamic> toJson() => {
    'name': name,
    'frameRegions': frameRegions,
    'frameDurationSeconds': frameDurationSeconds,
    'loop': loop,
    if (frameOffsetsX != null) 'frameOffsetsX': frameOffsetsX,
    if (frameOffsetsY != null) 'frameOffsetsY': frameOffsetsY,
    if (frameEvents != null)
      'frameEvents': [
        for (final frame in frameEvents!)
          [for (final e in frame) e.toJson()],
      ],
  };

  factory AnimationClip.fromJson(Map<String, dynamic> json) => AnimationClip(
    json['name'] as String,
    (json['frameRegions'] as List).cast<String>(),
    frameDurationSeconds:
        (json['frameDurationSeconds'] as num?)?.toDouble() ?? 0.1,
    loop: json['loop'] as bool? ?? true,
    frameOffsetsX: (json['frameOffsetsX'] as List?)
        ?.map((v) => (v as num).toDouble())
        .toList(),
    frameOffsetsY: (json['frameOffsetsY'] as List?)
        ?.map((v) => (v as num).toDouble())
        .toList(),
    frameEvents: (json['frameEvents'] as List?)
        ?.map(
          (frame) => (frame as List)
              .map(
                (e) => AnimationEvent.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList(),
        )
        .toList(),
  );
}

/// One data-driven cue attached to a single [AnimationClip] frame.
///
/// [type] is an opaque string (`sfx`, `hitbox_on`, `particle`, …);
/// [data] is the type-specific payload. `AnimationSystem` never
/// interprets these — it only wraps them in [AnimationFrameEvent].
class AnimationEvent {
  final String type;
  final Map<String, dynamic> data;

  const AnimationEvent(this.type, [this.data = const {}]);

  Map<String, dynamic> toJson() => {
    'type': type,
    if (data.isNotEmpty) 'data': data,
  };

  factory AnimationEvent.fromJson(Map<String, dynamic> json) => AnimationEvent(
    json['type'] as String,
    Map<String, dynamic>.from(
      (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
    ),
  );
}

/// Fired by `AnimationSystem` the tick playback enters a frame that
/// lists cues in [AnimationClip.frameEvents] — including the starting
/// frame of a freshly attached [AnimationState]. Subscribe with
/// `world.events.on<AnimationFrameEvent>(...)` for SFX, hitboxes, etc.
class AnimationFrameEvent {
  final EntityId entity;
  final String clipName;
  final String type;
  final Map<String, dynamic> data;
  final int frameIndex;

  AnimationFrameEvent(
    this.entity,
    this.clipName,
    this.type,
    this.data, {
    required this.frameIndex,
  });
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

  /// Frame index whose [AnimationClip.frameEvents] were already emitted
  /// for the current clip visit. `-1` means none yet — so attaching a
  /// fresh state (or swapping to a new [AnimationState]) fires cues on
  /// the starting frame, not only after the first advance. Runtime only;
  /// not serialized.
  int lastEmittedFrameIndex;

  AnimationState(
    this.clip, {
    this.frameIndex = 0,
    this.elapsed = 0,
    this.playing = true,
    this.crossfadeSeconds = 0,
    this.lastEmittedFrameIndex = -1,
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
