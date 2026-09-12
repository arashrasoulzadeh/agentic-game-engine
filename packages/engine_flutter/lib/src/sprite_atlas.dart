import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// One loaded sprite sheet plus named regions within it. Kept out of
/// engine_core because `dart:ui.Image` only exists in the Flutter
/// runtime — this is the boundary where the engine touches Flutter.
class SpriteAtlas {
  final ui.Image image;
  final Map<String, ui.Rect> regions;

  SpriteAtlas(this.image, this.regions);

  ui.Rect regionFor(String name) {
    final r = regions[name];
    if (r == null) {
      throw ArgumentError('SpriteAtlas has no region named "$name"');
    }
    return r;
  }

  /// Builds regions from a manifest shaped
  /// `{"regions": {"name": {"x":, "y":, "w":, "h":}}}` against an
  /// already-decoded [image]. Split out from [loadFromAssets] so the
  /// parsing logic is testable without real asset I/O.
  factory SpriteAtlas.fromManifest(ui.Image image, Map<String, dynamic> manifest) {
    final regionsJson = (manifest['regions'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final regions = <String, ui.Rect>{};
    regionsJson.forEach((name, value) {
      final r = (value as Map).cast<String, dynamic>();
      regions[name] = ui.Rect.fromLTWH(
        (r['x'] as num).toDouble(),
        (r['y'] as num).toDouble(),
        (r['w'] as num).toDouble(),
        (r['h'] as num).toDouble(),
      );
    });
    return SpriteAtlas(image, regions);
  }

  /// Loads a real sprite sheet: decodes [imageAssetPath] (any format
  /// `dart:ui` supports — PNG, JPEG, etc.) and reads named regions from
  /// [manifestAssetPath], a JSON asset in the manifest shape
  /// [fromManifest] expects. Both must be declared under `flutter.assets`
  /// in the game's `pubspec.yaml`.
  static Future<SpriteAtlas> loadFromAssets({
    required String imageAssetPath,
    required String manifestAssetPath,
  }) async {
    final manifestString = await rootBundle.loadString(manifestAssetPath);
    final manifest = jsonDecode(manifestString) as Map<String, dynamic>;

    final bytes = await rootBundle.load(imageAssetPath);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    final frame = await codec.getNextFrame();

    return SpriteAtlas.fromManifest(frame.image, manifest);
  }
}

/// Sprite/animation components store an atlas *id*, not a `SpriteAtlas`
/// instance, so they stay JSON-serializable (agent-editable) without
/// embedding a decoded image. This registry resolves ids to the actual
/// loaded atlas at render/apply time.
class AtlasRegistry {
  final Map<String, SpriteAtlas> _atlases = {};

  void register(String id, SpriteAtlas atlas) => _atlases[id] = atlas;

  SpriteAtlas resolve(String id) {
    final atlas = _atlases[id];
    if (atlas == null) {
      throw ArgumentError(
          'No SpriteAtlas registered for id "$id". Call registry.register() first.');
    }
    return atlas;
  }

  bool has(String id) => _atlases.containsKey(id);
}
