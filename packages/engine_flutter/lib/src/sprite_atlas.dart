import 'dart:ui' as ui;

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
