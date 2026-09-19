import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const channel = MethodChannel('xyz.luan/audioplayers');
  const global = MethodChannel('xyz.luan/audioplayers.global');
  late Directory tmp;
  late AudioCache oldCache;
  late List<MethodCall> calls;
  late List<String> players;

  Future<void> event(String id, String type, [Object? value]) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage('xyz.luan/audioplayers/events/$id',
      const StandardMethodCodec().encodeSuccessEnvelope({'event': type, 'value': value}),
      (_) => done.complete());
    await done.future;
    await Future<void>.delayed(Duration.zero);
  }

  setUp(() {
    calls = [];
    players = [];
    tmp = Directory.systemTemp.createTempSync('audio_playback_');
    final asset = File('${tmp.path}/tone.wav')..writeAsBytesSync([0, 1, 2, 3]);
    oldCache = AudioCache.instance;
    AudioCache.instance = AudioCache()..loadedFiles['tone.wav'] = asset.uri;
    messenger.setMockMethodCallHandler(global, (_) async => null);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      final args = (call.arguments as Map).cast<String, dynamic>();
      final id = args['playerId'] as String;
      if (call.method == 'create') {
        players.add(id);
        messenger.setMockMethodCallHandler(
          MethodChannel('xyz.luan/audioplayers/events/$id'), (_) async => null);
      }
      if (call.method == 'setSourceUrl') {
        scheduleMicrotask(() => event(id, 'audio.onPrepared', true));
      }
      if (call.method == 'getCurrentPosition' || call.method == 'getDuration') return 0;
      return null;
    });
  });

  tearDown(() async {
    await Future<void>.delayed(Duration.zero);
    for (final id in players) {
      messenger.setMockMethodCallHandler(MethodChannel('xyz.luan/audioplayers/events/$id'), null);
    }
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(global, null);
    AudioCache.instance = oldCache;
    tmp.deleteSync(recursive: true);
  });

  test('music forwards volume, loop mode and stop to the persistent player', () async {
    final audio = AudioManager();
    await audio.playMusic('tone.wav', volume: 0.4);
    await audio.setMusicVolume(0.2);
    await audio.stopMusic();
    await audio.playMusic('tone.wav', loop: false);
    expect(players, hasLength(1));
    final releases = calls.where((c) => c.method == 'setReleaseMode')
        .map((c) => (c.arguments as Map)['releaseMode']);
    expect(releases, containsAllInOrder(['ReleaseMode.loop', 'ReleaseMode.release']));
    expect(calls.where((c) => c.method == 'setVolume')
        .map((c) => (c.arguments as Map)['volume']), containsAllInOrder([0.4, 0.2, 1.0]));
    expect(calls.where((c) => c.method == 'stop'), isNotEmpty);
    audio.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls.where((c) => c.method == 'dispose'), hasLength(1));
  });

  test('completed sounds reuse players and excess idle players are disposed', () async {
    final audio = AudioManager();
    for (var i = 0; i < 9; i++) {
      await audio.playSound('tone.wav', volume: 0.6);
    }
    expect(players, hasLength(10)); // one music player and nine active sounds
    final effects = players.skip(1).toList();
    for (final id in effects) {
      await event(id, 'audio.onComplete');
    }
    expect(calls.where((c) => c.method == 'dispose')
        .map((c) => (c.arguments as Map)['playerId']), [effects.last]);
    await audio.playPositionalSound('tone.wav', sourceX: 50, sourceY: 0,
        listenerX: 0, listenerY: 0, maxDistance: 100, volume: 0.8);
    expect(players, hasLength(10));
    final balance = calls.lastWhere((c) => c.method == 'setBalance');
    expect((balance.arguments as Map)['balance'], 0.5);
    final volume = calls.lastWhere((c) => c.method == 'setVolume');
    expect((volume.arguments as Map)['volume'], 0.4);
    await event(effects[7], 'audio.onComplete');
    audio.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls.where((c) => c.method == 'dispose'), hasLength(10));
  });
}
