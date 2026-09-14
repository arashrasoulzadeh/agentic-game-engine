import 'dart:ui' as ui;

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _tinyImage() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(
    const Rect.fromLTWH(0, 0, 4, 4),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  return recorder.endRecording().toImage(4, 4);
}

void main() {
  test('fromManifest builds named regions from the manifest JSON', () async {
    final image = await _tinyImage();
    final atlas = SpriteAtlas.fromManifest(image, {
      'regions': {
        'idle': {'x': 0, 'y': 0, 'w': 16, 'h': 16},
        'walk_0': {'x': 16, 'y': 0, 'w': 16, 'h': 16},
      },
    });

    expect(atlas.regionFor('idle'), const Rect.fromLTWH(0, 0, 16, 16));
    expect(atlas.regionFor('walk_0'), const Rect.fromLTWH(16, 0, 16, 16));
  });

  test('fromManifest tolerates a missing "regions" key (empty atlas)', () async {
    final image = await _tinyImage();
    final atlas = SpriteAtlas.fromManifest(image, {});
    expect(atlas.regions, isEmpty);
  });

  test('regionFor throws ArgumentError for an unknown region name', () async {
    final image = await _tinyImage();
    final atlas = SpriteAtlas.fromManifest(image, {'regions': {}});
    expect(() => atlas.regionFor('missing'), throwsArgumentError);
  });

  test('loadFromAssets decodes the image and applies the manifest', () async {
    TestWidgetsFlutterBinding.ensureInitialized();

    final image = await _tinyImage();
    final pngBytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    const manifestJson = '{"regions": {"idle": {"x": 0, "y": 0, "w": 4, "h": 4}}}';

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final key = const StringCodec().decodeMessage(message);
      if (key == 'assets/manifest.json') {
        return const StringCodec().encodeMessage(manifestJson);
      }
      if (key == 'assets/sheet.png') {
        return ByteData.sublistView(pngBytes);
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    final atlas = await SpriteAtlas.loadFromAssets(
      imageAssetPath: 'assets/sheet.png',
      manifestAssetPath: 'assets/manifest.json',
    );

    expect(atlas.regionFor('idle'), const Rect.fromLTWH(0, 0, 4, 4));
    expect(atlas.image.width, 4);
  });

  test('AtlasRegistry.resolve throws ArgumentError for an unregistered id', () {
    final registry = AtlasRegistry();
    expect(() => registry.resolve('missing'), throwsArgumentError);
    expect(registry.has('missing'), isFalse);
  });

  test('AtlasRegistry.unregister removes the atlas and disposes its image', () async {
    final registry = AtlasRegistry();
    final atlas = SpriteAtlas.fromManifest(await _tinyImage(), {'regions': {}});
    registry.register('room1', atlas);
    expect(registry.has('room1'), isTrue);

    expect(registry.unregister('room1'), isTrue);
    expect(registry.has('room1'), isFalse);
    expect(() => registry.resolve('room1'), throwsArgumentError);
    // The underlying image is disposed -- touching its native handle
    // after disposal throws, proving unregister actually released the
    // GPU resource rather than just dropping the registry's own
    // reference to it (plain getters like .width read a cached field
    // and don't throw, so this checks a call that actually needs the
    // handle).
    expect(() => atlas.image.toByteData(), throwsA(anything));
  });

  test('AtlasRegistry.unregister on an id that was never registered is a harmless no-op',
      () {
    final registry = AtlasRegistry();
    expect(registry.unregister('missing'), isFalse);
  });
}
