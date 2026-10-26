import 'package:engine_core/engine_core.dart';

import '../rendering/animation_particle_system.dart';
import '../rendering/animation_shake_system.dart';
import '../rendering/camera.dart';
import 'animation_sfx_system.dart';
import 'audio_manager.dart';
import 'dialogue_sfx_system.dart';

/// Attaches the common [AnimationFrameEvent] / [PlaySoundEvent] bridges.
///
/// Registers optional systems on [world] and calls [AnimationSfxSystem.attach]
/// / [AnimationShakeSystem.attach] / [AnimationParticleSystem.attach] /
/// [DialogueSfxSystem.attach] so flushed frame and dialogue cues play.
/// Pass only the bridges you want — null skips that bridge.
void installAnimationCueSystems(
  World world, {
  AudioManager? audio,
  Camera? camera,
  Map<String, String> soundIds = const {},
  bool positionalSfx = false,
  bool includeParticles = true,
  bool includeDialogueSfx = true,
}) {
  if (audio != null) {
    final sfx = AnimationSfxSystem(
      audio,
      soundIds: soundIds,
      positional: positionalSfx,
    )..attach(world);
    world.addSystem(sfx);
    if (includeDialogueSfx) {
      final dialogue = DialogueSfxSystem(audio, soundIds: soundIds)
        ..attach(world);
      world.addSystem(dialogue);
    }
  }
  if (camera != null) {
    final shake = AnimationShakeSystem(camera)..attach(world);
    world.addSystem(shake);
  }
  if (includeParticles) {
    final particles = AnimationParticleSystem()..attach(world);
    world.addSystem(particles);
  }
}
