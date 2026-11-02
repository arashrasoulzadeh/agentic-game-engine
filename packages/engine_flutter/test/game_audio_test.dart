import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _Recorder implements AudioOutput {
  final calls = <String>[];
  @override
  Future<void> playSound(String assetPath, {double volume = 1.0}) async =>
      calls.add('sfx $assetPath $volume');
  @override
  Future<void> playMusic(
    String assetPath, {
    double volume = 1.0,
    bool loop = true,
  }) async => calls.add('music $assetPath $volume $loop');
  @override
  Future<void> stopMusic() async => calls.add('stop');
}

void main() {
  GameAudio make(_Recorder r) => GameAudio(
    r,
    sounds: {'jump': 'sfx/jump.wav'},
    tracks: {'theme': 'music/theme.mp3', 'boss': 'music/boss.mp3'},
  );

  test('names resolve to asset paths with master volumes applied', () async {
    final r = _Recorder();
    final audio = make(r)
      ..sfxVolume = 0.5
      ..musicVolume = 0.5;
    await audio.sfx('jump', volume: 0.5);
    await audio.music('theme', loop: false);
    expect(r.calls, [
      'sfx sfx/jump.wav 0.25',
      'music music/theme.mp3 0.5 false',
    ]);
  });

  test('asking for the playing track does not restart it', () async {
    final r = _Recorder();
    final audio = make(r);
    await audio.music('theme');
    await audio.music('theme');
    await audio.music('boss');
    expect(r.calls.where((c) => c.startsWith('music')), hasLength(2));
    expect(audio.currentTrack, 'boss');
    await audio.stopMusic();
    expect(audio.currentTrack, isNull);
    await audio.music('boss');
    expect(r.calls.where((c) => c.startsWith('music')), hasLength(3));
  });

  test(
    'unknown names throw listing the known ones, even when silent',
    () async {
      final audio = GameAudio.silent(sounds: {'jump': 'x'});
      await audio.sfx('jump');
      expect(
        () => audio.sfx('jmup'),
        throwsA(
          isA<ArgumentError>().having((e) => '$e', 'msg', contains('jump')),
        ),
      );
      expect(() => audio.music('theme'), throwsArgumentError);
    },
  );

  test('AudioManager can be used as the output', () {
    expect(<AudioManager>[], isA<List<AudioOutput>>());
  });
}
