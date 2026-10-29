import 'dart:convert';

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'fighters/pivots.dart';
import 'fx/fx.dart';

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

/// [loadMobarezSheet] plus each frame's feet [Pivot], for [FighterPivotSystem].
Future<({SpriteAtlas atlas, List<Pivot> pivots, double cell})>
loadMobarezSheetWithPivots(String assetStem) async {
  final meta =
      jsonDecode(await rootBundle.loadString('$assetStem.json'))
          as Map<String, dynamic>;
  final atlas = await loadMobarezSheet(assetStem);
  return (
    cell: (meta['cell'] as num).toDouble(),
    atlas: atlas,
    pivots: await atlasPivots(
      atlas,
      cell: (meta['cell'] as num).toInt(),
      gap: (meta['gap'] as num?)?.toInt() ?? 0,
      frames: (meta['frames'] as num?)?.toInt() ?? 1,
    ),
  );
}

/// Reads an effect sheet's sidecar into an [FxClip] registered under
/// [atlasId]; pair with `loadMobarezSheet(stem)` to register its image.
Future<FxClip> loadFxClip(String atlasId, String assetStem) async {
  final meta =
      jsonDecode(await rootBundle.loadString('$assetStem.json'))
          as Map<String, dynamic>;
  return FxClip(atlasId, (meta['frames'] as num?)?.toInt() ?? 1);
}
