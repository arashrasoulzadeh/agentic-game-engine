/// Request to play a one-shot SFX or VO clip.
///
/// Emitted by [DialogueRunner], cinematic [PlaySoundStep], and anything
/// else that wants audio without depending on Flutter. Listen with
/// `world.events.on<PlaySoundEvent>(...)` or attach `DialogueSfxSystem`
/// (name kept for the dialogue-era bridge; it handles every emitter).
class PlaySoundEvent {
  /// Key or asset path — games map keys through `DialogueSfxSystem.soundIds`.
  final String audioKey;

  /// Linear gain passed through to `AudioManager.playSound`.
  final double volume;

  PlaySoundEvent(this.audioKey, {this.volume = 1.0});
}
