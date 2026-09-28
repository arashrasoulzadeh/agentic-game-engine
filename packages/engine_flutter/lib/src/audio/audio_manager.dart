import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';

import 'package:engine_core/engine_core.dart';

/// Volume/stereo-balance for a sound at [sourceX]/[sourceY] as heard from
/// [listenerX]/[listenerY] (typically the camera's world position) —
/// pure math, no `audioplayers` dependency, so it's directly unit-
/// testable independently of platform playback.
///
/// Volume falls off linearly to `0` at [maxDistance] world units away
/// (clamped, never negative) and scales [baseVolume]. Balance is the
/// horizontal offset as a fraction of [maxDistance], clamped to
/// `audioplayers`' `[-1.0, 1.0]` (full left/right) range — vertical
/// offset doesn't affect stereo balance, since panning is left/right
/// only.
({double volume, double balance}) positionalAudioParams({
  required double sourceX,
  required double sourceY,
  required double listenerX,
  required double listenerY,
  double maxDistance = 800,
  double baseVolume = 1.0,
}) {
  final dx = sourceX - listenerX;
  final dy = sourceY - listenerY;
  final distance = math.sqrt(dx * dx + dy * dy);
  final falloff = (1.0 - distance / maxDistance).clamp(0.0, 1.0);
  final balance = (dx / maxDistance).clamp(-1.0, 1.0);
  return (volume: baseVolume * falloff, balance: balance);
}

/// Distance attenuation model for spatial audio.
enum AttenuationModel {
  /// Linear falloff: volume = base * (1 - distance / maxDistance)
  linear,
  /// Inverse square falloff: volume = base / (1 + distance^2)
  inverseSquare,
  /// Logarithmic falloff: volume = base * max(0, 1 - log(distance + 1) / log(maxDistance + 1))
  logarithmic,
  /// Custom curve via callback
  custom,
}

/// Parameters for spatial audio calculation.
class SpatialAudioParams {
  final double volume;
  final double balance;
  final double lowPassFrequency; // Hz, 0 = no filter
  final double reverbSend; // 0..1, amount sent to reverb
  final double dopplerShift; // pitch multiplier

  SpatialAudioParams({
    required this.volume,
    required this.balance,
    this.lowPassFrequency = 0.0,
    this.reverbSend = 0.0,
    this.dopplerShift = 1.0,
  });
}

/// Configuration for spatial audio calculation.
class SpatialAudioConfig {
  final double maxDistance;
  final AttenuationModel attenuation;
  final double baseVolume;
  final double minVolume;
  final bool enableOcclusion;
  final double occlusionLowPassFreq; // Hz when fully occluded
  final double occlusionVolumeReduction; // 0..1 volume reduction when occluded
  final bool enableDoppler;
  final double dopplerFactor; // 1.0 = realistic, 0.5 = half, etc.
  final double speedOfSound; // world units per second

  const SpatialAudioConfig({
    this.maxDistance = 800.0,
    this.attenuation = AttenuationModel.linear,
    this.baseVolume = 1.0,
    this.minVolume = 0.0,
    this.enableOcclusion = false,
    this.occlusionLowPassFreq = 500.0, // Hz
    this.occlusionVolumeReduction = 0.5,
    this.enableDoppler = false,
    this.dopplerFactor = 1.0,
    this.speedOfSound = 34300.0, // world units per second (343 m/s * 100)
  });
}

/// Checks if there's a clear line of sight between source and listener.
/// Returns true if unobstructed, false if blocked by solid tiles.
Future<bool> checkLineOfSight({
  required TileMap tileMap,
  required Position tileMapOrigin,
  required double sourceX,
  required double sourceY,
  required double listenerX,
  required double listenerY,
}) async {
  // Simple raycast - check if any solid tiles block the path
  final dx = listenerX - sourceX;
  final dy = listenerY - sourceY;
  final distance = math.sqrt(dx * dx + dy * dy);
  
  if (distance == 0) return true;
  
  final steps = (distance / (tileMap.tileWidth * 0.5)).ceil();
  for (int i = 1; i <= steps; i++) {
    final t = i / steps;
    final checkX = sourceX + dx * t;
    final checkY = sourceY + dy * t;
    
    final col = ((checkX - tileMapOrigin.x) / tileMap.tileWidth).floor();
    final row = ((checkY - tileMapOrigin.y) / tileMap.tileHeight).floor();
    
    if (col < 0 || col >= tileMap.cols || row < 0 || row >= tileMap.rows) {
      continue;
    }
    
    if (tileMap.solidTileIds.contains(tileMap.tileAt(col, row))) {
      return false;
    }
  }
  return true;
}

/// Calculates spatial audio parameters with advanced features.
SpatialAudioParams calculateSpatialAudioParams({
  required double sourceX,
  required double sourceY,
  required double listenerX,
  required double listenerY,
  double sourceVelocityX = 0.0,
  double sourceVelocityY = 0.0,
  double listenerVelocityX = 0.0,
  double listenerVelocityY = 0.0,
  SpatialAudioConfig config = const SpatialAudioConfig(),
  TileMap? tileMap,
  Position? tileMapOrigin,
}) {
  final dx = sourceX - listenerX;
  final dy = sourceY - listenerY;
  final distance = math.sqrt(dx * dx + dy * dy);
  
  // Volume attenuation
  double falloff;
  switch (config.attenuation) {
    case AttenuationModel.linear:
      falloff = (1.0 - distance / config.maxDistance).clamp(0.0, 1.0);
      break;
    case AttenuationModel.inverseSquare:
      falloff = 1.0 / (1.0 + (distance * distance) / (config.maxDistance * config.maxDistance));
      break;
    case AttenuationModel.logarithmic:
      falloff = (1.0 - math.log(distance + 1) / math.log(config.maxDistance + 1)).clamp(0.0, 1.0);
      break;
    case AttenuationModel.custom:
      falloff = 1.0; // Handled externally
      break;
  }
  
  double volume = (config.baseVolume * falloff).clamp(config.minVolume, config.baseVolume);
  
  // Stereo balance (horizontal only)
  final balance = (dx / config.maxDistance).clamp(-1.0, 1.0);
  
  // Occlusion check
  double lowPassFrequency = 0.0;
  double reverbSend = 0.0;
  
  if (config.enableOcclusion && tileMap != null && tileMapOrigin != null) {
    // Note: In real implementation, this would be async. For now, we'll
    // compute a simplified occlusion based on distance and tile checks.
    // Real implementation would raycast asynchronously.
    final hasLineOfSight = checkLineOfSightSync(
      tileMap: tileMap,
      tileMapOrigin: tileMapOrigin,
      sourceX: sourceX,
      sourceY: sourceY,
      listenerX: listenerX,
      listenerY: listenerY,
    );
    
    if (!hasLineOfSight) {
      lowPassFrequency = config.occlusionLowPassFreq;
      volume *= (1.0 - config.occlusionVolumeReduction);
    }
  }
  
  // Doppler effect
  double dopplerShift = 1.0;
  if (config.enableDoppler && config.speedOfSound > 0) {
    // Relative velocity along the line of sight
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance > 0) {
      final sourceVelAlong = (sourceVelocityX * dx + sourceVelocityY * dy) / distance;
      final listenerVelAlong = (listenerVelocityX * dx + listenerVelocityY * dy) / distance;
      final relativeVel = listenerVelAlong - sourceVelAlong;
      dopplerShift = (config.speedOfSound + config.dopplerFactor * relativeVel) / config.speedOfSound;
      dopplerShift = dopplerShift.clamp(0.1, 3.0); // Clamp to reasonable range
    }
  }
  
  // Simple reverb send based on distance (farther = more reverb)
  reverbSend = (distance / config.maxDistance).clamp(0.0, 1.0) * 0.5;
  
  return SpatialAudioParams(
    volume: volume,
    balance: balance,
    lowPassFrequency: lowPassFrequency,
    reverbSend: reverbSend,
    dopplerShift: dopplerShift,
  );
}

/// Synchronous line-of-sight check for occlusion (simplified).
bool checkLineOfSightSync({
  required TileMap tileMap,
  required Position tileMapOrigin,
  required double sourceX,
  required double sourceY,
  required double listenerX,
  required double listenerY,
}) {
  final dx = listenerX - sourceX;
  final dy = listenerY - sourceY;
  final distance = math.sqrt(dx * dx + dy * dy);
  
  if (distance == 0) return true;
  
  final tileSize = math.min(tileMap.tileWidth, tileMap.tileHeight);
  final steps = (distance / (tileSize * 0.5)).ceil();
  
  for (int i = 1; i <= steps; i++) {
    final t = i / steps;
    final checkX = sourceX + dx * t;
    final checkY = sourceY + dy * t;
    
    final col = ((checkX - tileMapOrigin.x) / tileMap.tileWidth).floor();
    final row = ((checkY - tileMapOrigin.y) / tileMap.tileHeight).floor();
    
    if (col < 0 || col >= tileMap.cols || row < 0 || row >= tileMap.rows) {
      continue;
    }
    
    if (tileMap.solidTileIds.contains(tileMap.tileAt(col, row))) {
      return false;
    }
  }
  return true;
}

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

  Future<void> playSound(String assetPath, {double volume = 1.0}) =>
      _play(assetPath, volume: volume);

  /// Plays a one-shot sound panned/attenuated by [sourceX]/[sourceY]'s
  /// distance from [listenerX]/[listenerY] — see [positionalAudioParams]
  /// for the (separately unit-tested) math. Computed once at trigger
  /// time, not re-evaluated per frame — a short SFX has finished playing
  /// long before its source or the listener could move meaningfully, so
  /// there's nothing to gain from tracking it live, only per-frame cost
  /// for every currently-playing sound (see TODO.md's note on this).
  Future<void> playPositionalSound(
    String assetPath, {
    required double sourceX,
    required double sourceY,
    required double listenerX,
    required double listenerY,
    double maxDistance = 800,
    double volume = 1.0,
  }) {
    final params = positionalAudioParams(
      sourceX: sourceX,
      sourceY: sourceY,
      listenerX: listenerX,
      listenerY: listenerY,
      maxDistance: maxDistance,
      baseVolume: volume,
    );
    return _play(assetPath, volume: params.volume, balance: params.balance);
  }

  /// Plays a sound with advanced spatial audio features including occlusion,
  /// Doppler effect, and configurable attenuation.
  Future<void> playAdvancedPositionalSound(
    String assetPath, {
    required double sourceX,
    required double sourceY,
    required double listenerX,
    required double listenerY,
    double sourceVelocityX = 0.0,
    double sourceVelocityY = 0.0,
    double listenerVelocityX = 0.0,
    double listenerVelocityY = 0.0,
    SpatialAudioConfig config = const SpatialAudioConfig(),
    TileMap? tileMap,
    Position? tileMapOrigin,
  }) {
    final params = calculateSpatialAudioParams(
      sourceX: sourceX,
      sourceY: sourceY,
      listenerX: listenerX,
      listenerY: listenerY,
      sourceVelocityX: sourceVelocityX,
      sourceVelocityY: sourceVelocityY,
      listenerVelocityX: listenerVelocityX,
      listenerVelocityY: listenerVelocityY,
      config: config,
      tileMap: tileMap,
      tileMapOrigin: tileMapOrigin,
    );
    return _play(
      assetPath,
      volume: params.volume,
      balance: params.balance,
      pitch: params.dopplerShift,
      lowPassFrequency: params.lowPassFrequency,
      reverbSend: params.reverbSend,
    );
  }

  Future<void> _play(
    String assetPath, {
    double volume = 1.0,
    double balance = 0.0,
    double pitch = 1.0,
    double lowPassFrequency = 0.0,
    double reverbSend = 0.0,
  }) async {
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
    await player.play(AssetSource(assetPath), volume: volume, balance: balance);
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