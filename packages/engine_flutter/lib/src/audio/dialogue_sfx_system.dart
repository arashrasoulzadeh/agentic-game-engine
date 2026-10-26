import 'package:engine_core/engine_core.dart';

import 'audio_manager.dart';

/// Plays one-shots for [PlaySoundEvent] (dialogue VO/choice SFX, cinematic
/// [PlaySoundStep], or anything else that emits the event).
///
/// Call [attach] once on the world those systems advance against.
/// [update] is a no-op — playback is event-driven.
///
/// [soundIds] maps event [PlaySoundEvent.audioKey] → asset path;
/// unmapped keys are treated as asset paths directly.
class DialogueSfxSystem implements System {
  /// Maps audio keys → asset paths. Unmapped keys are used as paths.
  final Map<String, String> soundIds;

  final Future<void> Function(String assetPath, {double volume}) _playSound;

  bool _attached = false;

  /// Production constructor — wires [AudioManager.playSound].
  DialogueSfxSystem(
    AudioManager audio, {
    this.soundIds = const {},
  }) : _playSound = audio.playSound;

  /// Test / custom playback without constructing [AudioManager].
  DialogueSfxSystem.custom({
    required Future<void> Function(String assetPath, {double volume}) playSound,
    this.soundIds = const {},
  }) : _playSound = playSound;

  @override
  String get name => 'dialogueSfx';

  /// Registers the handler on [world]. Safe to call more than once —
  /// subsequent calls are no-ops.
  void attach(World world) {
    if (_attached) return;
    _attached = true;
    world.events.on<PlaySoundEvent>((event) {
      final path = soundIds[event.audioKey] ?? event.audioKey;
      if (path.isEmpty) return;
      _playSound(path, volume: event.volume);
    });
  }

  @override
  void update(World world, double dt) {
    // Event-driven — see [attach].
  }
}
