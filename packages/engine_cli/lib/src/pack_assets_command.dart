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
        help: 'Sheet width the row packer wraps at. A single source image '
            'wider than this still gets its own row at its own width — '
            'this is a target, not a hard cap.',
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

    final packed = _pack(items, padding: padding, maxWidth: maxWidth);

    final outputImageFile = File(outputImagePath);
    outputImageFile.parent.createSync(recursive: true);
    outputImageFile.writeAsBytesSync(img.encodePng(packed.sheet));

    final outputManifestFile = File(outputManifestPath);
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
      '$outputImagePath: packed ${items.length} images into '
      '${packed.sheet.width}x${packed.sheet.height} '
      '(manifest: $outputManifestPath)',
    );
    return 0;
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

  /// Simple deterministic row/shelf packer: widest-first within each
  /// row, wrapping to a new row (as tall as its tallest item) once
  /// [maxWidth] would be exceeded. Not as dense as a true bin-packer
  /// (e.g. MaxRects), but the sheet is a build artifact regenerated by
  /// `pack-assets` itself, not hand-tuned or committed art — a
  /// predictable, easy-to-reason-about layout matters more here than
  /// squeezing out the last few percent of texture memory.
  _PackedSheet _pack(List<_PackItem> items, {required int padding, required int maxWidth}) {
    final sorted = [...items]..sort((a, b) => b.image.height.compareTo(a.image.height));

    var cursorX = padding;
    var cursorY = padding;
    var rowHeight = 0;
    var sheetWidth = 0;
    final placements = <String, _Rect>{};

    for (final item in sorted) {
      final w = item.image.width;
      final h = item.image.height;
      if (cursorX + w + padding > maxWidth && cursorX > padding) {
        cursorX = padding;
        cursorY += rowHeight + padding;
        rowHeight = 0;
      }
      placements[item.name] = _Rect(cursorX, cursorY, w, h);
      cursorX += w + padding;
      rowHeight = rowHeight < h ? h : rowHeight;
      sheetWidth = sheetWidth < cursorX ? cursorX : sheetWidth;
    }
    final sheetHeight = cursorY + rowHeight + padding;

    final sheet = img.Image(width: sheetWidth, height: sheetHeight, numChannels: 4);
    for (final item in sorted) {
      final rect = placements[item.name]!;
      img.compositeImage(sheet, item.image,
          dstX: rect.x, dstY: rect.y, blend: img.BlendMode.direct);
    }

    return _PackedSheet(sheet, placements);
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
