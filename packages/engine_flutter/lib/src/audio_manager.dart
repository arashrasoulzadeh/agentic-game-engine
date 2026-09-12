import 'package:audioplayers/audioplayers.dart';

/// Sound effect + music playback. Kept out of engine_core the same way
/// rendering/input are — it's a platform capability, not simulation
/// state. The recommended pattern is to listen on `world.events`
/// (games already emit their own domain events, e.g. a `CollisionEvent`
/// or a game-defined `EnemyDefeatedEvent`) and call `playSound` from
/// that listener, rather than triggering audio from inside a System —
/// keeps simulation logic decoupled from playback.
///
/// One-shot sound effects each get a short-lived `AudioPlayer` that
/// disposes itself on completion, so overlapping SFX don't cut each
/// other off. Music uses a single persistent player since a game
/// typically has one music track playing at a time.
class AudioManager {
  final AudioPlayer _music = AudioPlayer();

  Future<void> playSound(String assetPath, {double volume = 1.0}) async {
    final player = AudioPlayer();
    player.onPlayerComplete.listen((_) => player.dispose());
    await player.play(AssetSource(assetPath), volume: volume);
  }

  Future<void> playMusic(
    String assetPath, {
    double volume = 1.0,
    bool loop = true,
  }) async {
    await _music.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
    await _music.play(AssetSource(assetPath), volume: volume);
  }

  Future<void> stopMusic() => _music.stop();

  Future<void> setMusicVolume(double volume) => _music.setVolume(volume);

  void dispose() {
    _music.dispose();
  }
}
