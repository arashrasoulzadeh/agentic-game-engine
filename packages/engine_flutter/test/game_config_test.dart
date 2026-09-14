import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadFromAsset reads and decodes the bundled JSON asset', () async {
    const jsonContent = '{"worldWidth": 320, "worldHeight": 240, "title": "Asset Game"}';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      return const StringCodec().encodeMessage(jsonContent);
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    final config = await GameConfig.loadFromAsset('assets/game_config.json');

    expect(config.title, 'Asset Game');
    expect(config.worldWidth, 320);
    expect(config.worldHeight, 240);
  });

  test('applyOrientation requests the platform orientation for portrait/landscape/auto',
      () async {
    final requests = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        requests.add(call.method);
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    for (final orientation in GameOrientation.values) {
      await GameConfig(orientation: orientation, worldWidth: 1, worldHeight: 1)
          .applyOrientation();
    }

    expect(requests.length, GameOrientation.values.length);
  });

  test('round-trips through toJson/fromJson', () {
    const config = GameConfig(
      title: 'My Game',
      orientation: GameOrientation.landscape,
      worldWidth: 800,
      worldHeight: 600,
      backgroundColor: Colors.red,
      showFpsOverlay: true,
      showColliderDebug: true,
      pauseOnBackground: false,
      onScreenControls: OnScreenControlsMode.on,
      ambientBrightness: 0.3,
      maxFps: 60,
    );

    final restored = GameConfig.fromJson(config.toJson());

    expect(restored.title, 'My Game');
    expect(restored.orientation, GameOrientation.landscape);
    expect(restored.worldWidth, 800);
    expect(restored.worldHeight, 600);
    expect(restored.backgroundColor.toARGB32(), Colors.red.toARGB32());
    expect(restored.showFpsOverlay, isTrue);
    expect(restored.showColliderDebug, isTrue);
    expect(restored.pauseOnBackground, isFalse);
    expect(restored.onScreenControls, OnScreenControlsMode.on);
    expect(restored.ambientBrightness, 0.3);
    expect(restored.maxFps, 60);
  });

  test('fromJson falls back to defaults for missing/unknown fields', () {
    final config = GameConfig.fromJson({
      'worldWidth': 100,
      'worldHeight': 200,
      'orientation': 'not-a-real-value',
    });

    expect(config.title, 'Game');
    expect(config.orientation, GameOrientation.auto);
    expect(config.worldWidth, 100);
    expect(config.worldHeight, 200);
    expect(config.showFpsOverlay, isFalse);
    expect(config.showColliderDebug, isFalse);
    expect(config.pauseOnBackground, isTrue);
    expect(config.onScreenControls, OnScreenControlsMode.auto);
    expect(config.ambientBrightness, 1.0);
    expect(config.maxFps, isNull);
  });

  test('maxFps null (default) is omitted from toJson entirely, not serialized as null', () {
    const config = GameConfig(worldWidth: 1, worldHeight: 1);
    expect(config.toJson().containsKey('maxFps'), isFalse);
  });
}
