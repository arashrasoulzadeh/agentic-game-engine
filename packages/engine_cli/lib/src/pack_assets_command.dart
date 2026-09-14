import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// One source image queued for packing — decoded up front so the
/// packer can sort/place by real pixel dimensions before doing any
/// actual compositing.
class _PackItem {
  final String name;
  final img.Image image;
  _PackItem(this.name, this.image);
}

/// Combines every image under an input directory (recursively — a
/// game's level art is typically split across subfolders per level/
/// character/tileset, and all of it belongs in one atlas) into a
/// single packed sprite sheet PNG plus a JSON region manifest, run as
/// a pre-build step ahead of `flutter run`/`flutter build` rather than
/// loading one `SpriteAtlas` per source image at runtime — see
/// `GameConfig.packedAtlasId`'s doc comment (`engine_flutter`) for how
/// a game actually consumes the result.
///
/// The manifest is written in exactly the shape
/// `SpriteAtlas.fromManifest` (`engine_flutter`) already reads for a
/// hand-authored atlas — `{"regions": {"name": {"x","y","w","h"}}}` —
/// so no new parsing/loading code was needed on the consuming side at
/// all, only a place to point it at.
///
/// `--scales` (default `1.0`, i.e. one tier, today's original behavior)
/// packs one additional resized sheet+manifest pair per extra tier —
/// see its own `--help` text for the naming convention and why
/// *picking* a tier at runtime is left to the game, not decided here.
class PackAssetsCommand extends Command<int> {
  @override
  final name = 'pack-assets';
  @override
  final description =
      'Pack every image under a directory into one sprite sheet + manifest, '
      'for GameConfig.packedAtlasId (run before flutter run/build).';

  PackAssetsCommand() {
    argParser
      ..addOption(
        'input',
        abbr: 'i',
        help: 'Directory to scan recursively for images (.png/.jpg/.jpeg/.bmp/.gif).',
      )
      ..addOption(
        'output-image',
        abbr: 'o',
        defaultsTo: 'assets/packed/atlas.png',
        help: 'Where to write the packed sprite sheet PNG.',
      )
      ..addOption(
        'output-manifest',
        abbr: 'm',
        help: 'Where to write the region manifest JSON. Defaults to '
            '--output-image with a .json extension.',
      )
      ..addOption(
        'padding',
        defaultsTo: '2',
        help: 'Transparent pixels left between packed regions, to avoid '
            'texture-filtering bleed between adjacent sprites at runtime.',
      )
      ..addOption(
        'max-width',
        defaultsTo: '2048',
        help: 'Starting width hint for the packer (it grows the sheet as '
            'needed if this turns out too small for everything to fit) — '
            'not a hard cap on the final sheet width.',
      )
      ..addOption(
        'scales',
        defaultsTo: '1.0',
        help: 'Comma-separated resolution tiers to pack, e.g. "1.0,0.5,0.25" '
            '-- each source image is resized (before packing, so the packer '
            'still sees real post-resize dimensions) and written to its own '
            'sheet + manifest pair, letting a mobile game load a smaller '
            'sheet when its sprites are shown well under native size instead '
            'of always paying full source-resolution texture memory/'
            'bandwidth. The 1.0 tier (always implied even if omitted) keeps '
            'the plain --output-image/--output-manifest paths unchanged; '
            'every other tier gets an "@<scale>x" suffix inserted before the '
            'extension (e.g. atlas.png -> atlas@0.5x.png). Picking which '
            'tier to load at runtime (screen density, an explicit config) '
            'is the consuming game\'s decision, not this command\'s -- it '
            'only produces the tiers, matching the same "@2x/@3x" naming '
            'convention Flutter\'s own asset-variant system uses.',
      );
  }

  @override
  Future<int> run() async {
    final args = argResults!;
    final inputPath = args['input'] as String?;
    if (inputPath == null) {
      stderr.writeln(
        'Error: missing --input, e.g. `game_agent pack-assets --input assets/images`',
      );
      return 1;
    }

    final inputDir = Directory(inputPath);
    if (!inputDir.existsSync()) {
      stderr.writeln('Error: ${inputDir.path} does not exist.');
      return 1;
    }

    final outputImagePath = args['output-image'] as String;
    final outputManifestPath =
        (args['output-manifest'] as String?) ?? _defaultManifestPath(outputImagePath);
    final padding = int.parse(args['padding'] as String);
    final maxWidth = int.parse(args['max-width'] as String);
    final List<double> scales;
    try {
      scales = (args['scales'] as String)
          .split(',')
          .map((s) => double.parse(s.trim()))
          .toList();
    } on FormatException {
      stderr.writeln('Error: --scales must be a comma-separated list of numbers, '
          'e.g. "1.0,0.5,0.25" (got "${args['scales']}").');
      return 1;
    }
    if (scales.any((s) => s <= 0)) {
      stderr.writeln('Error: --scales values must be > 0 (got "${args['scales']}").');
      return 1;
    }

    final items = _loadItems(inputDir);
    if (items.isEmpty) {
      stderr.writeln('Error: no images found under ${inputDir.path}.');
      return 1;
    }

    final duplicate = _findDuplicateName(items);
    if (duplicate != null) {
      stderr.writeln(
        'Error: two source images both resolve to region name "$duplicate" '
        '(region names are the file\'s basename without extension, so e.g. '
        'levels/1/coin.png and levels/2/coin.png collide) — rename one.',
      );
      return 1;
    }

    for (final scale in scales) {
      final scaledItems = scale == 1.0 ? items : _resized(items, scale);
      final packed = _pack(scaledItems, padding: padding, maxWidth: maxWidth);

      final imagePath = _tieredPath(outputImagePath, scale);
      final manifestPath = _tieredPath(outputManifestPath, scale);

      final outputImageFile = File(imagePath);
      outputImageFile.parent.createSync(recursive: true);
      outputImageFile.writeAsBytesSync(img.encodePng(packed.sheet));

      final outputManifestFile = File(manifestPath);
      outputManifestFile.parent.createSync(recursive: true);
      outputManifestFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'regions': {
            for (final entry in packed.regions.entries)
              entry.key: {
                'x': entry.value.x,
                'y': entry.value.y,
                'w': entry.value.w,
                'h': entry.value.h,
              },
          },
        }),
      );

      stdout.writeln(
        '$imagePath: packed ${scaledItems.length} images into '
        '${packed.sheet.width}x${packed.sheet.height} '
        '(manifest: $manifestPath)',
      );
    }
    return 0;
  }

  /// Resizes every item to [scale] of its original dimensions (at least
  /// 1px per side, so a tiny source image at a small scale never
  /// resolves to a degenerate 0x0 region) — a fresh list, the original
  /// full-resolution `items` list (and its decoded images) is left
  /// untouched for the next scale tier's own resize pass.
  List<_PackItem> _resized(List<_PackItem> items, double scale) => [
        for (final item in items)
          _PackItem(
            item.name,
            img.copyResize(
              item.image,
              width: (item.image.width * scale).round().clamp(1, 1 << 20),
              height: (item.image.height * scale).round().clamp(1, 1 << 20),
            ),
          ),
      ];

  /// `scale == 1.0` returns [path] unchanged (the plain, un-suffixed
  /// tier every existing caller already expects); any other scale
  /// inserts an `@<scale>x` suffix before the extension, e.g.
  /// `atlas.png` + `0.5` -> `atlas@0.5x.png` — the same convention
  /// Flutter's own `2.0x`/`3.0x` asset-variant folders use, just applied
  /// to a filename instead of a directory since each tier here is a
  /// whole separate sheet+manifest pair, not a same-named variant asset.
  String _tieredPath(String path, double scale) {
    if (scale == 1.0) return path;
    final dir = p.dirname(path);
    final ext = p.extension(path);
    final base = p.basenameWithoutExtension(path);
    final scaleLabel = scale == scale.roundToDouble()
        ? scale.toStringAsFixed(0)
        : scale.toString();
    return p.join(dir, '$base@${scaleLabel}x$ext');
  }

  static const _imageExtensions = {'.png', '.jpg', '.jpeg', '.bmp', '.gif'};

  List<_PackItem> _loadItems(Directory inputDir) {
    final items = <_PackItem>[];
    final files = inputDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => _imageExtensions.contains(p.extension(f.path).toLowerCase()))
        .toList()
      // Deterministic packing order regardless of filesystem iteration
      // order -- otherwise the same input directory can pack into a
      // different-shaped sheet from one run to the next, which would
      // make the output PNG (and its git diff) churn for no reason.
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final file in files) {
      final decoded = img.decodeImage(file.readAsBytesSync());
      if (decoded == null) continue; // not actually a decodable image despite the extension
      items.add(_PackItem(p.basenameWithoutExtension(file.path), decoded));
    }
    return items;
  }

  String? _findDuplicateName(List<_PackItem> items) {
    final seen = <String>{};
    for (final item in items) {
      if (!seen.add(item.name)) return item.name;
    }
    return null;
  }

  /// MaxRects bin-packer (Best Short Side Fit heuristic — for each item,
  /// place it in whichever free rectangle leaves the smallest leftover
  /// short side, which in practice keeps leftover gaps close to
  /// square/reusable rather than long slivers). Replaced an earlier
  /// row/shelf packer: a shelf packer wastes a real, measurable amount
  /// of space whenever items in the same row have very different
  /// heights (a whole row is only as efficient as its tallest item,
  /// even for a narrow item next to a tall one) — MaxRects instead
  /// tracks the actual leftover free space as a set of rectangles and
  /// can tuck a small item into a gap a shelf packer would've left
  /// empty. [maxWidth] no longer caps a row — it's now the starting bin
  /// width for the grow-and-retry loop below, kept as the same CLI flag
  /// name/meaning (an initial size hint) since a caller relying on it to
  /// roughly bound sheet width shouldn't need to change anything.
  _PackedSheet _pack(List<_PackItem> items, {required int padding, required int maxWidth}) {
    // Every item's own placement footprint includes its trailing
    // padding, so free-rect splitting naturally leaves the right gap
    // between adjacent placements without special-casing it at draw
    // time.
    final sorted = [...items]
      ..sort((a, b) {
        final areaCompare =
            (b.image.width + padding) * (b.image.height + padding) -
                (a.image.width + padding) * (a.image.height + padding);
        return areaCompare != 0 ? areaCompare : a.name.compareTo(b.name);
      });

    final totalArea = sorted.fold<int>(
        0, (sum, item) => sum + (item.image.width + padding) * (item.image.height + padding));
    final maxItemWidth =
        sorted.fold<int>(0, (m, item) => item.image.width + padding > m ? item.image.width + padding : m);
    final maxItemHeight =
        sorted.fold<int>(0, (m, item) => item.image.height + padding > m ? item.image.height + padding : m);

    var binWidth = [maxWidth, maxItemWidth, _ceilSqrt(totalArea)].reduce((a, b) => a > b ? a : b);
    var binHeight = [maxItemHeight, _ceilSqrt(totalArea)].reduce((a, b) => a > b ? a : b);

    Map<String, _Rect>? placements;
    // Grow-and-retry: an initial size estimate can still be too tight
    // for a particular mix of aspect ratios: capped, not unbounded, so
    // a genuine bug elsewhere can't spin forever.
    for (var attempt = 0; attempt < 20 && placements == null; attempt++) {
      placements = _tryPack(sorted, padding, binWidth, binHeight);
      if (placements == null) {
        binWidth = (binWidth * 1.25).ceil();
        binHeight = (binHeight * 1.25).ceil();
      }
    }
    if (placements == null) {
      throw StateError('pack-assets: failed to fit ${sorted.length} images after 20 grow '
          'attempts (last tried ${binWidth}x$binHeight) -- this should not happen; '
          'please report it.');
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

    final sheet = img.Image(width: sheetWidth, height: sheetHeight, numChannels: 4);
    for (final item in sorted) {
      final rect = placements[item.name]!;
      img.compositeImage(sheet, item.image,
          dstX: rect.x, dstY: rect.y, blend: img.BlendMode.direct);
    }

    return _PackedSheet(sheet, placements);
  }

  /// One packing attempt at a fixed [binWidth]/[binHeight] — returns
  /// `null` (never partial) the moment any item doesn't fit anywhere,
  /// so the caller can grow the bin and start clean rather than reason
  /// about a half-packed state.
  Map<String, _Rect>? _tryPack(List<_PackItem> sorted, int padding, int binWidth, int binHeight) {
    final freeRects = <_Rect>[_Rect(0, 0, binWidth, binHeight)];
    final placements = <String, _Rect>{};

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
      if (bestIndex == -1) return null; // doesn't fit anywhere at this bin size

      final chosen = freeRects[bestIndex];
      final placed = _Rect(chosen.x, chosen.y, w, h);
      placements[item.name] = _Rect(placed.x, placed.y, item.image.width, item.image.height);

      // Split every free rect that overlaps the newly placed rect into
      // the (up to 4) leftover pieces around it, then drop the ones
      // that ended up fully contained in another -- otherwise the free
      // list grows unboundedly and later fit checks slow down.
      final next = <_Rect>[];
      for (final free in freeRects) {
        if (!_overlaps(free, placed)) {
          next.add(free);
          continue;
        }
        if (placed.x > free.x) {
          next.add(_Rect(free.x, free.y, placed.x - free.x, free.h));
        }
        if (placed.x + placed.w < free.x + free.w) {
          next.add(_Rect(
              placed.x + placed.w, free.y, free.x + free.w - (placed.x + placed.w), free.h));
        }
        if (placed.y > free.y) {
          next.add(_Rect(free.x, free.y, free.w, placed.y - free.y));
        }
        if (placed.y + placed.h < free.y + free.h) {
          next.add(_Rect(
              free.x, placed.y + placed.h, free.w, free.y + free.h - (placed.y + placed.h)));
        }
      }
      freeRects
        ..clear()
        ..addAll(next.where((r) => r.w > 0 && r.h > 0));
      _pruneContained(freeRects);
    }
    return placements;
  }

  bool _overlaps(_Rect a, _Rect b) =>
      a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;

  bool _contains(_Rect outer, _Rect inner) =>
      inner.x >= outer.x &&
      inner.y >= outer.y &&
      inner.x + inner.w <= outer.x + outer.w &&
      inner.y + inner.h <= outer.y + outer.h;

  void _pruneContained(List<_Rect> rects) {
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

  String _defaultManifestPath(String outputImagePath) {
    final dir = p.dirname(outputImagePath);
    final base = p.basenameWithoutExtension(outputImagePath);
    return p.join(dir, '$base.json');
  }
}

class _Rect {
  final int x, y, w, h;
  _Rect(this.x, this.y, this.w, this.h);
}

class _PackedSheet {
  final img.Image sheet;
  final Map<String, _Rect> regions;
  _PackedSheet(this.sheet, this.regions);
}
