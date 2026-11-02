import 'audio_manager.dart';

/// The playback calls [GameAudio] needs, so it works over the real
/// [AudioManager] in a game and over a recording fake in tests.
abstract class AudioOutput {
  /// Plays a one-shot sound from asset [assetPath].
  Future<void> playSound(String assetPath, {double volume = 1.0});

  /// Starts background music from asset [assetPath].
  Future<void> playMusic(
    String assetPath, {
    double volume = 1.0,
    bool loop = true,
  });

  /// Stops the background music.
  Future<void> stopMusic();
}

/// Plays sounds and music by short name: `audio.sfx('jump')`,
/// `audio.music('theme')`, instead of passing asset paths through game code.
///
/// Names are checked even when nothing is audible, so a typo fails in a
/// headless test rather than going silently missing on a device. Use
/// [GameAudio.silent] for servers, tests and CLIs: every call validates the
/// name and then does nothing.
///
/// ```dart
/// final audio = GameAudio(
///   AudioManager(),
///   sounds: {'jump': 'sfx/jump.wav'},
///   tracks: {'theme': 'music/theme.mp3'},
/// );
/// audio.sfx('jump');
/// audio.music('theme');
/// ```
class GameAudio {
  final AudioOutput? _output;
  final Map<String, String> sounds;
  final Map<String, String> tracks;

  /// Master volume multiplier for sound effects (0..1).
  double sfxVolume = 1.0;

  /// Master volume multiplier for music (0..1).
  double musicVolume = 1.0;

  String? _currentTrack;

  /// Plays through [output] using the given name -> asset path maps.
  GameAudio(
    AudioOutput output, {
    this.sounds = const {},
    this.tracks = const {},
  }) : _output = output;

  /// Validates names but makes no sound.
  GameAudio.silent({this.sounds = const {}, this.tracks = const {}})
    : _output = null;

  /// The track started by the last [music] call, or null.
  String? get currentTrack => _currentTrack;

  /// Plays the sound registered as [name] at [volume] (times [sfxVolume]).
  /// Throws an [ArgumentError] listing the known names if [name] is unknown.
  Future<void> sfx(String name, {double volume = 1.0}) async {
    final path = _lookup(sounds, name, 'sound');
    await _output?.playSound(path, volume: volume * sfxVolume);
  }

  /// Starts the track registered as [name]. Asking for the track that is
  /// already playing does nothing, so scenes can call it on every entry
  /// without restarting the music.
  Future<void> music(
    String name, {
    double volume = 1.0,
    bool loop = true,
  }) async {
    final path = _lookup(tracks, name, 'track');
    if (_currentTrack == name) return;
    _currentTrack = name;
    await _output?.playMusic(path, volume: volume * musicVolume, loop: loop);
  }

  /// Stops the music and forgets the current track.
  Future<void> stopMusic() async {
    _currentTrack = null;
    await _output?.stopMusic();
  }

  static String _lookup(Map<String, String> map, String name, String kind) {
    final path = map[name];
    if (path != null) return path;
    final known = (map.keys.toList()..sort()).join(', ');
    throw ArgumentError.value(
      name,
      kind,
      'No $kind registered under this name. Known: '
      '${known.isEmpty ? '(none)' : known}.',
    );
  }
}
