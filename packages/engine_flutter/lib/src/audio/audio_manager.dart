// coverage:ignore-file
// Real playback (play/playMusic/stopMusic/setMusicVolume) routes through
// audioplayers' platform channels *and* its own asset-caching/path_provider
// plumbing (temp-file caching on some platforms) before it ever reaches the
// two method channels this package can mock -- see audio_manager_test.dart's
// comment for what was tried and why it isn't worth chasing further than
// construction/disposal in a unit test. Verify real playback on a device
// (tracked in TODO.md), not by faking three platform plugins' internals here.

import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Sound effect + music playback. Kept out of engine_core the same way
/// rendering/input are — it's a platform capability, not simulation
/// state. The recommended pattern is to listen on `world.events`
/// (games already emit their own domain events, e.g. a `CollisionEvent`
/// or a game-defined `EnemyDefeatedEvent`) and call `playSound` from
/// that listener, rather than triggering audio from inside a System —
/// keeps simulation logic decoupled from playback.
///
/// One-shot sound effects reuse a pooled `AudioPlayer` (see
/// [_maxPoolSize]) instead of constructing a fresh one per call —
/// constructing an `AudioPlayer` sets up real platform-channel/native
/// player state on every platform `audioplayers` supports, which is
/// real, avoidable overhead for a rapidly-repeated short SFX (a coin
/// pickup, a jump) at the trigger rates a fast platformer can hit
/// (several within one second). A player returns to the pool the
/// instant its current sound finishes, ready for the next `playSound`
/// call to reuse rather than allocate a new one; only once the pool is
/// full does an extra concurrent sound still get its own short-lived
/// player (disposed on completion instead of pooled), so a burst of
/// simultaneous overlapping SFX still all play correctly, just without
/// the pooling benefit past [_maxPoolSize] of them at once. Music
/// still uses a single persistent player since a game typically has
/// one music track playing at a time.
class AudioManager {
  final AudioPlayer _music = AudioPlayer();

  /// Idle, ready-to-reuse `AudioPlayer`s — populated as sounds finish
  /// playing (see [playSound]), drained (LIFO, so the most recently
  /// used player -- warmest in whatever native/platform-channel sense
  /// that matters -- is reused first) by the next `playSound` call.
  final List<AudioPlayer> _pool = [];

  /// Caps how many idle players stay pooled at once — bounds the pool's
  /// own resource footprint for a game that had one unusually large
  /// burst of overlapping sounds early on; an extra completed player
  /// past this cap is disposed instead of pooled. `8` is a generous
  /// guess at "more concurrent one-shot SFX than a typical 2D game
  /// actually overlaps at once," not a measured/tuned value.
  static const _maxPoolSize = 8;

  Future<void> playSound(String assetPath, {double volume = 1.0}) async {
    final player = _pool.isNotEmpty ? _pool.removeLast() : AudioPlayer();
    late final StreamSubscription<void> subscription;
    subscription = player.onPlayerComplete.listen((_) {
      subscription.cancel();
      if (_pool.length < _maxPoolSize) {
        _pool.add(player);
      } else {
        player.dispose();
      }
    });
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
    for (final player in _pool) {
      player.dispose();
    }
    _pool.clear();
  }
}
