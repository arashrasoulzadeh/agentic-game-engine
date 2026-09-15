import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Fully simulating audioplayers' platform channels (including the
  // event channels it waits on internally to confirm playback) is a
  // deep rabbit hole for low payoff here — actual sound output is a
  // platform-integration concern better verified on a real device
  // (tracked in TODO.md) than faked in a unit test. This just confirms
  // construction (which itself calls the platform to create a native
  // player) and disposal complete without throwing.
  setUp(() {
    for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  tearDown(() {
    for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  test('AudioManager constructs and disposes without throwing', () async {
    final audio = AudioManager();
    audio.dispose();
    // dispose() fires AudioPlayer.dispose() (async, not awaited by design --
    // it's a void fire-and-forget API) which does its own platform-channel
    // round trip internally; without this pump, that pending call can
    // resolve after this test hands off to the next one, whose tearDown
    // has already torn down the mock channel handler -- flaky failure this
    // test would otherwise blame on "disposes without throwing".
    await Future<void>.delayed(Duration.zero);
  });

  // Exercising playSound()'s new pooling path (a player actually
  // completing, returning to the pool, and being reused) was tried
  // here and reverted -- play() goes all the way through
  // audioplayers' AudioCache to a real asset-bundle load before this
  // mock (a bare method-channel stub with no asset/event-channel
  // simulation) is ever reached, throwing "Unable to load asset" for
  // any path that doesn't exist in the test bundle. Exactly the same
  // rabbit hole this file's own top comment already flags for
  // play/playMusic/stopMusic/setMusicVolume -- not worth chasing
  // further than construction/disposal in a unit test; real playback
  // (pooled or not) is verified on a device instead (tracked in
  // TODO.md).

  group('positionalAudioParams', () {
    test('a source at the listener plays at full base volume, centered balance', () {
      final params = positionalAudioParams(
        sourceX: 100,
        sourceY: 50,
        listenerX: 100,
        listenerY: 50,
        baseVolume: 0.8,
      );
      expect(params.volume, 0.8);
      expect(params.balance, 0);
    });

    test('volume falls off linearly with distance and hits zero at maxDistance', () {
      final half = positionalAudioParams(
        sourceX: 400,
        sourceY: 0,
        listenerX: 0,
        listenerY: 0,
        maxDistance: 800,
      );
      expect(half.volume, closeTo(0.5, 1e-9));

      final atEdge = positionalAudioParams(
        sourceX: 800,
        sourceY: 0,
        listenerX: 0,
        listenerY: 0,
        maxDistance: 800,
      );
      expect(atEdge.volume, 0);
    });

    test('volume never goes negative past maxDistance', () {
      final params = positionalAudioParams(
        sourceX: 5000,
        sourceY: 0,
        listenerX: 0,
        listenerY: 0,
        maxDistance: 800,
      );
      expect(params.volume, 0);
    });

    test('a source to the right pans right (positive balance), left pans left', () {
      final right = positionalAudioParams(
        sourceX: 400,
        sourceY: 0,
        listenerX: 0,
        listenerY: 0,
        maxDistance: 800,
      );
      expect(right.balance, greaterThan(0));

      final left = positionalAudioParams(
        sourceX: -400,
        sourceY: 0,
        listenerX: 0,
        listenerY: 0,
        maxDistance: 800,
      );
      expect(left.balance, lessThan(0));
    });

    test('balance clamps to [-1, 1] even far outside maxDistance', () {
      final params = positionalAudioParams(
        sourceX: 10000,
        sourceY: 0,
        listenerX: 0,
        listenerY: 0,
        maxDistance: 800,
      );
      expect(params.balance, 1.0);
    });

    test('purely vertical offset does not affect balance', () {
      final params = positionalAudioParams(
        sourceX: 0,
        sourceY: 500,
        listenerX: 0,
        listenerY: 0,
        maxDistance: 800,
      );
      expect(params.balance, 0);
    });
  });
}
