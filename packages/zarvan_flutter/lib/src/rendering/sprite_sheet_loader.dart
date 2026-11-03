import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'one_shot_fx.dart';
import 'sprite_atlas.dart';
import 'sprite_pivots.dart';

/// A strip sheet's sidecar `<stem>.json`: the grid it was packed on. Frame
/// `i` is the `cell`-sized square at `x = gap + i * (cell + gap)`.
class SheetSidecar {
  const SheetSidecar({required this.cell, this.gap = 0, this.frames = 1});

  final int cell;
  final int gap;
  final int frames;

  factory SheetSidecar.fromJson(Map<String, dynamic> json) => SheetSidecar(
    cell: (json['cell'] as num).toInt(),
    gap: (json['gap'] as num?)?.toInt() ?? 0,
    frames: (json['frames'] as num?)?.toInt() ?? 1,
  );
}

/// A loaded strip sheet with its sidecar and each frame's [Pivot].
class LoadedSheet {
  const LoadedSheet({
    required this.atlas,
    required this.sidecar,
    required this.pivots,
  });

  final SpriteAtlas atlas;
  final SheetSidecar sidecar;
  final List<Pivot> pivots;
}

/// Reads `<assetStem>.json`.
Future<SheetSidecar> loadSheetSidecar(String assetStem) async =>
    SheetSidecar.fromJson(
      jsonDecode(await rootBundle.loadString('$assetStem.json'))
          as Map<String, dynamic>,
    );

/// Loads `<assetStem>.png` as a strip atlas laid out by its sidecar
/// `<assetStem>.json`, so a game ships art + a tiny JSON instead of passing
/// cell/gap/frame counts around in code. With [measurePivots] it also
/// measures each frame's feet for `SpritePivotSystem`.
Future<LoadedSheet> loadSpriteSheet(
  String assetStem, {
  bool measurePivots = true,
}) async {
  final sidecar = await loadSheetSidecar(assetStem);
  final atlas = await SpriteAtlas.loadStripFromAssets(
    imageAssetPath: '$assetStem.png',
    cell: sidecar.cell,
    frames: sidecar.frames,
    gap: sidecar.gap,
  );
  return LoadedSheet(
    atlas: atlas,
    sidecar: sidecar,
    pivots: measurePivots
        ? await atlasPivots(
            atlas,
            cell: sidecar.cell,
            gap: sidecar.gap,
            frames: sidecar.frames,
          )
        : const [],
  );
}

/// An [FxClip] for an effect sheet, with its frame count from the sidecar.
/// Register the image separately with `loadSpriteSheet(stem, measurePivots:
/// false)`.
Future<FxClip> loadFxClip(String atlasId, String assetStem) async =>
    FxClip(atlasId, (await loadSheetSidecar(assetStem)).frames);
