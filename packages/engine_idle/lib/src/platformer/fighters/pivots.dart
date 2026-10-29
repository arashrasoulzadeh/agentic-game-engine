import 'dart:typed_data';

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' hide Text;

import '../combat/fighter_anims.dart';

/// Where a frame's character stands inside its cell: [x] is the centre of
/// the feet, [y] the lowest opaque row, [top] the highest. Pixel units of the
/// unscaled sheet.
class Pivot {
  const Pivot(this.x, this.y, [this.top = 0]);
  final double x;
  final double y;
  final double top;
}

/// Finds each frame's [Pivot] in an RGBA strip (`gap + i*(cell+gap)` layout).
///
/// Sheets are cropped per pose (a thrust reaches far, a collapse is low), so
/// the character's feet land in a different spot of every cell and drawing
/// cell-centred makes it slide and bob. The feet are the stable part: X is the
/// mean of opaque pixels in the bottom [footFraction] of the frame's bounding
/// box (not its bbox centre, which a spear would drag sideways).
List<Pivot> sheetPivots(
  Uint8List rgba,
  int width,
  int height, {
  required int cell,
  required int gap,
  required int frames,
  double footFraction = 0.12,
  int alphaCutoff = 16,
}) {
  final out = <Pivot>[];
  for (var f = 0; f < frames; f++) {
    final x0 = gap + f * (cell + gap);
    var top = -1;
    var bottom = -1;
    for (var y = 0; y < height; y++) {
      for (var x = x0; x < x0 + cell && x < width; x++) {
        if (rgba[(y * width + x) * 4 + 3] > alphaCutoff) {
          if (top < 0) top = y;
          bottom = y;
          break;
        }
      }
    }
    if (bottom < 0) {
      out.add(Pivot(cell / 2, cell.toDouble()));
      continue;
    }
    final footTop = bottom - ((bottom - top + 1) * footFraction).ceil() + 1;
    var sum = 0.0;
    var n = 0;
    for (var y = footTop; y <= bottom; y++) {
      for (var x = x0; x < x0 + cell && x < width; x++) {
        if (rgba[(y * width + x) * 4 + 3] > alphaCutoff) {
          sum += x - x0 + 0.5;
          n++;
        }
      }
    }
    out.add(Pivot(sum / n, bottom + 1.0, top.toDouble()));
  }
  return out;
}

/// Reads [atlas]'s pixels and returns its frames' [Pivot]s.
Future<List<Pivot>> atlasPivots(
  SpriteAtlas atlas, {
  required int cell,
  required int gap,
  required int frames,
}) async {
  final data = await atlas.image.toByteData();
  return sheetPivots(
    data!.buffer.asUint8List(),
    atlas.image.width,
    atlas.image.height,
    cell: cell,
    gap: gap,
    frames: frames,
  );
}

/// A fighter's standing silhouette in its sheet's pixels, from idle frame 0.
typedef Body = ({double x, double bottom, double top, double cell});

/// Pivots per atlas id, filled as sheets load.
class PivotTable {
  final Map<String, List<Pivot>> _byAtlas = {};
  final Map<String, double> _cells = {};

  void register(String atlasId, List<Pivot> pivots, {double cell = 64}) {
    _byAtlas[atlasId] = pivots;
    _cells[atlasId] = cell;
  }

  /// The standing silhouette of [atlasId]'s first frame, if loaded.
  Body? bodyOf(String atlasId) {
    final p = _byAtlas[atlasId]?.first;
    final cell = _cells[atlasId];
    if (p == null || cell == null) return null;
    return (x: p.x, bottom: p.y, top: p.top, cell: cell);
  }

  /// Sprite offset that keeps [region] of [atlasId] standing where
  /// [referenceAtlasId]'s first frame stands, or null if either is unknown.
  ({double x, double y})? offsetFor(
    String atlasId,
    String region,
    String referenceAtlasId,
  ) {
    final ref = _byAtlas[referenceAtlasId]?.first;
    final frames = _byAtlas[atlasId];
    final i = int.tryParse(region);
    if (ref == null || frames == null || i == null || i >= frames.length) {
      return null;
    }
    return (x: ref.x - frames[i].x, y: ref.y - frames[i].y);
  }
}

/// Pins each fighter's feet to one spot across frames and states using
/// [table]. Register right after `AnimationSystem`, which resets the offsets
/// it writes each tick.
class FighterPivotSystem extends System {
  FighterPivotSystem(this.table);

  final PivotTable table;

  @override
  String get name => 'fighterPivot';

  @override
  void update(World world, double dt) {
    final anims = world.storeOf<FighterAnims>();
    final sprites = world.storeOf<Sprite>();
    for (var i = 0; i < anims.length; i++) {
      final sprite = sprites.get(anims.entityAt(i));
      final idle = anims.denseAt(i).clips['idle'];
      if (sprite == null || idle == null) continue;
      final o = table.offsetFor(sprite.atlasId, sprite.region, idle.atlasId);
      if (o == null) continue;
      sprite.offsetX = o.x;
      sprite.offsetY = o.y;
    }
  }
}
