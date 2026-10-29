import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;
import 'package:engine_platformer/engine_platformer.dart';

/// One playable state (`idle`, `attack`, `death`, …) of a fighter: which
/// sheet it lives in and how it plays. Each state is its own sprite sheet,
/// so playing it means swapping the [Sprite]'s atlas as well as its clip.
class FighterClip {
  const FighterClip({
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

  factory FighterClip.fromJson(Map<String, dynamic> json) => FighterClip(
    atlasId: json['atlasId'] as String,
    frames: (json['frames'] as num).toInt(),
    loop: json['loop'] as bool? ?? false,
    frameSeconds: (json['frameSeconds'] as num?)?.toDouble() ?? 0.1,
  );
}

/// A fighter's animation states plus which one is playing. Game and combat
/// code request a state with [playFighterAnim]; [FighterAnimationSystem]
/// performs the swap, returns one-shot states to `idle`, and holds `death`.
class FighterAnims {
  FighterAnims(this.clips, {this.current = 'idle', this.requested});

  final Map<String, FighterClip> clips;
  String current;
  String? requested;

  Map<String, dynamic> toJson() => {
    'clips': {for (final e in clips.entries) e.key: e.value.toJson()},
    'current': current,
  };

  factory FighterAnims.fromJson(Map<String, dynamic> json) => FighterAnims({
    for (final e in (json['clips'] as Map).entries)
      e.key as String: FighterClip.fromJson(
        (e.value as Map).cast<String, dynamic>(),
      ),
  }, current: json['current'] as String? ?? 'idle');
}

/// Asks [entity] to play [state]. Ignored once it is dead, and when the
/// fighter has no such clip (e.g. an enemy without a `hit` sheet).
void playFighterAnim(World world, EntityId entity, String state) {
  final a = world.storeOf<FighterAnims>().get(entity);
  if (a == null || a.current == 'death' || !a.clips.containsKey(state)) return;
  a.requested = state;
}

/// True once [entity]'s `death` clip has played to its last frame.
bool fighterDeathFinished(World world, EntityId entity) {
  final a = world.storeOf<FighterAnims>().get(entity);
  final s = world.storeOf<AnimationState>().get(entity);
  return a != null && a.current == 'death' && s != null && !s.playing;
}

/// Applies [FighterAnims] requests. Register before `AnimationSystem` so the
/// new clip's first frame is drawn the same tick.
class FighterAnimationSystem extends System {
  @override
  String get name => 'fighterAnimation';

  @override
  void update(World world, double dt) {
    final anims = world.storeOf<FighterAnims>();
    final health = world.storeOf<Health>();
    final states = world.storeOf<AnimationState>();
    for (var i = 0; i < anims.length; i++) {
      final e = anims.entityAt(i);
      final a = anims.denseAt(i);
      final hp = health.get(e);
      if (hp != null && hp.current <= 0 && a.current != 'death') {
        a.requested = 'death';
      }
      final next =
          a.requested ??
          (a.current != 'idle' &&
                  a.current != 'death' &&
                  !(states.get(e)?.playing ?? true)
              ? 'idle'
              : null);
      a.requested = null;
      if (next != null) _play(world, e, a, next);
    }
  }

  void _play(World world, EntityId e, FighterAnims a, String state) {
    final clip = a.clips[state];
    final sprite = world.storeOf<Sprite>().get(e);
    if (clip == null || sprite == null) return;
    a.current = state;
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
