import 'dart:convert';

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Loads a Mobarez sheet sidecar (`cell` / `gap` / `frames`) via the
/// engine's [SpriteAtlas.fromStrip] / [SpriteAtlas.loadStripFromAssets].
Future<SpriteAtlas> loadMobarezSheet(String assetStem) async {
  final meta =
      jsonDecode(await rootBundle.loadString('$assetStem.json'))
          as Map<String, dynamic>;
  return SpriteAtlas.loadStripFromAssets(
    imageAssetPath: '$assetStem.png',
    cell: (meta['cell'] as num).toInt(),
    frames: (meta['frames'] as num?)?.toInt() ?? 1,
    gap: (meta['gap'] as num?)?.toInt() ?? 0,
  );
}

/// Full-image atlas for backgrounds — engine [SpriteAtlas.loadFullImageFromAssets].
Future<SpriteAtlas> loadFullImageAtlas(String imageAssetPath) =>
    SpriteAtlas.loadFullImageFromAssets(imageAssetPath);
