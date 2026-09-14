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

  test('AudioManager constructs and disposes without throwing', () {
    final audio = AudioManager();
    audio.dispose();
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
}
