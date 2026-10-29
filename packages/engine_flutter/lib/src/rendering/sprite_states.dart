import 'package:engine_core/engine_core.dart';

import 'animation.dart';
import 'sprite.dart';

/// One named state of a [SpriteStates] entity: the sheet it lives in and how
/// it plays. Regions are the strip convention `'0'..'frames-1'`.
class SpriteClip {
  const SpriteClip({
    required this.atlasId,
    required this.frames,
    this.loop = false,
    this.frameSeconds = 0.1,
  });

  final String atlasId;
  final int frames;
  final bool loop;
  final double frameSeconds;

  Map<String, dynamic> toJson() => {
    'atlasId': atlasId,
    'frames': frames,
    'loop': loop,
    'frameSeconds': frameSeconds,
  };

  factory SpriteClip.fromJson(Map<String, dynamic> json) => SpriteClip(
    atlasId: json['atlasId'] as String,
    frames: (json['frames'] as num).toInt(),
    loop: json['loop'] as bool? ?? false,
    frameSeconds: (json['frameSeconds'] as num?)?.toDouble() ?? 0.1,
  );
}

/// A sprite's animation states (`idle`, `attack`, `death`, …) and which is
/// playing.
///
/// Hand-painted characters usually ship one sheet per state, so changing
/// state means swapping the [Sprite]'s atlas as well as its clip — which a
/// plain [AnimationState] cannot do. Game code asks for a state with
/// [playSpriteState]; [SpriteStateSystem] performs the swap, sends one-shot
/// states back to [restState], and freezes [holdStates] (e.g. `death`) on
/// their last frame.
class SpriteStates {
  SpriteStates(
    this.clips, {
    this.current = 'idle',
    this.requested,
    this.restState = 'idle',
    Set<String>? holdStates,
  }) : holdStates = holdStates ?? {'death'};

  final Map<String, SpriteClip> clips;
  String current;

  /// State to switch to on the next tick, set by [playSpriteState].
  String? requested;

  /// State a finished one-shot returns to.
  final String restState;

  /// States that, once entered, are never left.
  final Set<String> holdStates;

  Map<String, dynamic> toJson() => {
    'clips': {for (final e in clips.entries) e.key: e.value.toJson()},
    'current': current,
    'restState': restState,
    'holdStates': holdStates.toList(),
  };

  factory SpriteStates.fromJson(Map<String, dynamic> json) => SpriteStates(
    {
      for (final e in (json['clips'] as Map).entries)
        e.key as String: SpriteClip.fromJson(
          (e.value as Map).cast<String, dynamic>(),
        ),
    },
    current: json['current'] as String? ?? 'idle',
    restState: json['restState'] as String? ?? 'idle',
    holdStates: (json['holdStates'] as List?)?.cast<String>().toSet(),
  );
}

/// Asks [entity] to switch to [state]. Ignored once it is in a hold state,
/// and when it has no such clip (e.g. an enemy without a `hit` sheet).
void playSpriteState(World world, EntityId entity, String state) {
  final s = world.storeOf<SpriteStates>().get(entity);
  if (s == null ||
      s.holdStates.contains(s.current) ||
      !s.clips.containsKey(state)) {
    return;
  }
  s.requested = state;
}

/// True once [entity] is in [state] and that clip has played its last frame.
bool spriteStateFinished(World world, EntityId entity, String state) {
  final s = world.storeOf<SpriteStates>().get(entity);
  final a = world.storeOf<AnimationState>().get(entity);
  return s != null && s.current == state && a != null && !a.playing;
}

/// Applies [SpriteStates] requests. Register before `AnimationSystem` so a
/// new clip's first frame is drawn the same tick.
class SpriteStateSystem extends System {
  @override
  String get name => 'spriteState';

  @override
  void update(World world, double dt) {
    final states = world.storeOf<SpriteStates>();
    final anims = world.storeOf<AnimationState>();
    for (var i = 0; i < states.length; i++) {
      final e = states.entityAt(i);
      final s = states.denseAt(i);
      final finishedOneShot =
          s.current != s.restState &&
          !s.holdStates.contains(s.current) &&
          !(anims.get(e)?.playing ?? true);
      final next = s.requested ?? (finishedOneShot ? s.restState : null);
      s.requested = null;
      if (next != null) _play(world, e, s, next);
    }
  }

  void _play(World world, EntityId e, SpriteStates s, String state) {
    final clip = s.clips[state];
    final sprite = world.storeOf<Sprite>().get(e);
    if (clip == null || sprite == null) return;
    s.current = state;
    sprite.atlasId = clip.atlasId;
    sprite.region = '0';
    world.storeOf<AnimationState>().set(
      e,
      AnimationState(
        AnimationClip(
          state,
          [for (var i = 0; i < clip.frames; i++) '$i'],
          frameDurationSeconds: clip.frameSeconds,
          loop: clip.loop,
        ),
      ),
    );
  }
}
