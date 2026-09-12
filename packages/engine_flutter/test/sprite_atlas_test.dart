import 'dart:ui' as ui;

import 'package:engine_flutter/engine_flutter.dart';
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

  test('AtlasRegistry.resolve throws ArgumentError for an unregistered id', () {
    final registry = AtlasRegistry();
    expect(() => registry.resolve('missing'), throwsArgumentError);
    expect(registry.has('missing'), isFalse);
  });
}
