import 'image_codec.dart';

/// One source image queued for packing, already decoded.
class PackItem {
  const PackItem(this.name, this.image);

  /// Region name in the manifest (usually the file basename without extension).
  final String name;
  final EngineImage image;
}

/// Axis-aligned placement of one region on the packed sheet (pixels, no padding).
class PackRect {
  const PackRect(this.x, this.y, this.w, this.h);

  final int x, y, w, h;

  Map<String, int> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};
}

/// Result of [packAtlas]: the composited sheet and every region's rectangle.
class PackedAtlas {
  const PackedAtlas(this.sheet, this.regions);

  final EngineImage sheet;
  final Map<String, PackRect> regions;
}

/// MaxRects bin-packer (Best Short Side Fit): for each item, place it in whichever free
/// rectangle leaves the smallest leftover short side. Replaced an earlier row/shelf packer
/// that wasted space whenever items in the same row had different heights.
///
/// [maxWidth] is a starting bin-width hint (the packer grows as needed), not a hard cap.
/// [maxAttempts] bounds the grow-and-retry loop so a genuine bug cannot spin forever.
PackedAtlas packAtlas(
  ImageCodec codec,
  List<PackItem> items, {
  int padding = 2,
  int maxWidth = 2048,
  int maxAttempts = 20,
}) {
  if (items.isEmpty) {
    throw ArgumentError('packAtlas needs at least one image');
  }
  final sorted = [...items]
    ..sort((a, b) {
      final areaCompare =
          (b.image.width + padding) * (b.image.height + padding) -
          (a.image.width + padding) * (a.image.height + padding);
      return areaCompare != 0 ? areaCompare : a.name.compareTo(b.name);
    });

  final totalArea = sorted.fold<int>(
    0,
    (sum, item) =>
        sum + (item.image.width + padding) * (item.image.height + padding),
  );
  final maxItemWidth = sorted.fold<int>(
    0,
    (m, item) =>
        item.image.width + padding > m ? item.image.width + padding : m,
  );
  final maxItemHeight = sorted.fold<int>(
    0,
    (m, item) =>
        item.image.height + padding > m ? item.image.height + padding : m,
  );

  var binWidth = [
    maxWidth,
    maxItemWidth,
    _ceilSqrt(totalArea),
  ].reduce((a, b) => a > b ? a : b);
  var binHeight = [
    maxItemHeight,
    _ceilSqrt(totalArea),
  ].reduce((a, b) => a > b ? a : b);

  Map<String, PackRect>? placements;
  for (
    var attempt = 0;
    attempt < maxAttempts && placements == null;
    attempt++
  ) {
    placements = _tryPack(sorted, padding, binWidth, binHeight);
    if (placements == null) {
      binWidth = (binWidth * 1.25).ceil();
      binHeight = (binHeight * 1.25).ceil();
    }
  }
  if (placements == null) {
    throw StateError(
      'packAtlas: failed to fit ${sorted.length} images after $maxAttempts grow '
      'attempts (last tried ${binWidth}x$binHeight)',
    );
  }

  var sheetWidth = 0;
  var sheetHeight = 0;
  for (final rect in placements.values) {
    final right = rect.x + rect.w;
    final bottom = rect.y + rect.h;
    if (right > sheetWidth) sheetWidth = right;
    if (bottom > sheetHeight) sheetHeight = bottom;
  }
  sheetWidth += padding;
  sheetHeight += padding;

  final sheet = codec.create(sheetWidth, sheetHeight);
  for (final item in sorted) {
    final rect = placements[item.name]!;
    codec.composite(sheet, item.image, dstX: rect.x, dstY: rect.y);
  }
  return PackedAtlas(sheet, placements);
}

Map<String, PackRect>? _tryPack(
  List<PackItem> sorted,
  int padding,
  int binWidth,
  int binHeight,
) {
  final freeRects = <_BinRect>[_BinRect(0, 0, binWidth, binHeight)];
  final placements = <String, PackRect>{};

  for (final item in sorted) {
    final w = item.image.width + padding;
    final h = item.image.height + padding;

    var bestIndex = -1;
    var bestShortSideFit = 1 << 30;
    var bestLongSideFit = 1 << 30;
    for (var i = 0; i < freeRects.length; i++) {
      final free = freeRects[i];
      if (free.w < w || free.h < h) continue;
      final leftoverW = free.w - w;
      final leftoverH = free.h - h;
      final shortSide = leftoverW < leftoverH ? leftoverW : leftoverH;
      final longSide = leftoverW < leftoverH ? leftoverH : leftoverW;
      if (shortSide < bestShortSideFit ||
          (shortSide == bestShortSideFit && longSide < bestLongSideFit)) {
        bestIndex = i;
        bestShortSideFit = shortSide;
        bestLongSideFit = longSide;
      }
    }
    if (bestIndex == -1) return null;

    final chosen = freeRects[bestIndex];
    final placed = _BinRect(chosen.x, chosen.y, w, h);
    placements[item.name] = PackRect(
      placed.x,
      placed.y,
      item.image.width,
      item.image.height,
    );

    final next = <_BinRect>[];
    for (final free in freeRects) {
      if (!_overlaps(free, placed)) {
        next.add(free);
        continue;
      }
      if (placed.x > free.x) {
        next.add(_BinRect(free.x, free.y, placed.x - free.x, free.h));
      }
      if (placed.x + placed.w < free.x + free.w) {
        next.add(
          _BinRect(
            placed.x + placed.w,
            free.y,
            free.x + free.w - (placed.x + placed.w),
            free.h,
          ),
        );
      }
      if (placed.y > free.y) {
        next.add(_BinRect(free.x, free.y, free.w, placed.y - free.y));
      }
      if (placed.y + placed.h < free.y + free.h) {
        next.add(
          _BinRect(
            free.x,
            placed.y + placed.h,
            free.w,
            free.y + free.h - (placed.y + placed.h),
          ),
        );
      }
    }
    freeRects
      ..clear()
      ..addAll(next.where((r) => r.w > 0 && r.h > 0));
    _pruneContained(freeRects);
  }
  return placements;
}

bool _overlaps(_BinRect a, _BinRect b) =>
    a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;

bool _contains(_BinRect outer, _BinRect inner) =>
    inner.x >= outer.x &&
    inner.y >= outer.y &&
    inner.x + inner.w <= outer.x + outer.w &&
    inner.y + inner.h <= outer.y + outer.h;

void _pruneContained(List<_BinRect> rects) {
  for (var i = 0; i < rects.length; i++) {
    for (var j = i + 1; j < rects.length; j++) {
      if (_contains(rects[j], rects[i])) {
        rects.removeAt(i);
        i--;
        break;
      }
      if (_contains(rects[i], rects[j])) {
        rects.removeAt(j);
        j--;
      }
    }
  }
}

int _ceilSqrt(int area) {
  if (area <= 0) return 1;
  var x = 1;
  while (x * x < area) {
    x++;
  }
  return x;
}

class _BinRect {
  final int x, y, w, h;
  _BinRect(this.x, this.y, this.w, this.h);
}

/// Inserts an `@<scale>x` suffix before the extension when [scale] is not 1.0
/// (`atlas.png` + `0.5` → `atlas@0.5x.png`); the 1.0 tier keeps [path] unchanged.
String tieredAtlasPath(String path, double scale) {
  if (scale == 1.0) return path;
  final slash = path.lastIndexOf('/');
  final dir = slash < 0 ? '' : path.substring(0, slash + 1);
  final file = slash < 0 ? path : path.substring(slash + 1);
  final dot = file.lastIndexOf('.');
  final base = dot < 0 ? file : file.substring(0, dot);
  final ext = dot < 0 ? '' : file.substring(dot);
  final scaleLabel = scale == scale.roundToDouble()
      ? scale.toStringAsFixed(0)
      : scale.toString();
  return '$dir$base@${scaleLabel}x$ext';
}

/// Default manifest path beside an image path (`atlas.png` → `atlas.json`).
String defaultManifestPath(String outputImagePath) {
  final slash = outputImagePath.lastIndexOf('/');
  final dir = slash < 0 ? '' : outputImagePath.substring(0, slash + 1);
  final file = slash < 0 ? outputImagePath : outputImagePath.substring(slash + 1);
  final dot = file.lastIndexOf('.');
  final base = dot < 0 ? file : file.substring(0, dot);
  return '${dir}$base.json';
}
