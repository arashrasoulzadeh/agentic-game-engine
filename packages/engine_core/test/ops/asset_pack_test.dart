import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:engine_core/engine_core_ops.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Minimal raster: solid colour, no `package:image` dependency in core tests.
class _FakeImage implements EngineImage {
  _FakeImage(this.width, this.height, this.r, this.g, this.b);
  @override
  final int width;
  @override
  final int height;
  final int r, g, b;
}

class _FakeCodec implements ImageCodec {
  @override
  EngineImage? decode(Uint8List bytes) {
    // Tiny custom header: 'FAKE' + w + h + r + g + b (7 bytes after magic).
    if (bytes.length < 11) return null;
    if (bytes[0] != 0x46 || bytes[1] != 0x41 || bytes[2] != 0x4B || bytes[3] != 0x45) {
      return null;
    }
    return _FakeImage(bytes[4], bytes[5], bytes[6], bytes[7], bytes[8]);
  }

  @override
  EngineImage resize(EngineImage source, double scale) {
    final s = source as _FakeImage;
    return _FakeImage(
      (s.width * scale).round().clamp(1, 1 << 20),
      (s.height * scale).round().clamp(1, 1 << 20),
      s.r,
      s.g,
      s.b,
    );
  }

  @override
  EngineImage create(int width, int height) => _FakeImage(width, height, 0, 0, 0);

  @override
  void fill(EngineImage image, EngineColor color) {}

  @override
  void fillRect(
    EngineImage image, {
    required int x1,
    required int y1,
    required int x2,
    required int y2,
    required EngineColor color,
  }) {}

  @override
  void fillCircle(
    EngineImage image, {
    required int x,
    required int y,
    required int radius,
    required EngineColor color,
  }) {}

  @override
  void drawString(
    EngineImage image,
    String text, {
    required int x,
    required int y,
    required EngineColor color,
  }) {}

  @override
  void composite(
    EngineImage dest,
    EngineImage src, {
    required int dstX,
    required int dstY,
  }) {
    // Placement-only tests don't inspect pixels; compositing is a no-op.
  }

  @override
  Uint8List encodePng(EngineImage image) {
    final i = image as _FakeImage;
    // Not a real PNG — enough for write/undo round-trips in MemoryFiles/DiskFiles.
    return Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      i.width,
      i.height,
      i.r,
      i.g,
      i.b,
    ]);
  }
}

Uint8List _fakeBytes(int w, int h, int r, int g, int b) =>
    Uint8List.fromList([0x46, 0x41, 0x4B, 0x45, w, h, r, g, b, 0, 0]);

void main() {
  late Directory tmp;
  late OperationRegistry registry;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('asset_pack_');
    registry = buildRegistry();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  OpContext ctx({ImageCodec? codec}) => OpContext(
    project: ProjectRoot(tmp.path),
    actor: 'test',
    imageCodec: codec,
  );

  test('without a codec returns unsupported', () async {
    final r = await registry.call('asset.pack', {
      'input': 'src',
      'apply': true,
    }, ctx());
    expect(r.ok, isFalse);
    expect(r.error!.code, ErrorCode.unsupported);
  });

  test('packs images into a sheet + manifest and is undoable', () async {
    final coin = File(p.join(tmp.path, 'src', 'coin.png'))
      ..createSync(recursive: true);
    coin.writeAsBytesSync(_fakeBytes(8, 8, 255, 215, 0));
    final crate = File(p.join(tmp.path, 'src', 'level', 'crate.png'))
      ..createSync(recursive: true);
    crate.writeAsBytesSync(_fakeBytes(16, 12, 139, 69, 19));

    final r = await registry.call('asset.pack', {
      'input': 'src',
      'outputImage': 'out/atlas.png',
      'outputManifest': 'out/atlas.json',
      'apply': true,
    }, ctx(codec: _FakeCodec()));
    if (!r.ok) {
      fail('${r.error?.toJson()}');
    }
    final atlas = File(p.join(tmp.path, 'out', 'atlas.png'));
    if (!atlas.existsSync()) {
      fail(
        'ok but no atlas; data=${r.data} diff=${r.diff} '
        'tree=${Directory(tmp.path).listSync(recursive: true).map((e) => e.path).toList()}',
      );
    }
    final manifest =
        jsonDecode(
              File(p.join(tmp.path, 'out', 'atlas.json')).readAsStringSync(),
            )
            as Map;
    expect((manifest['regions'] as Map).keys.toSet(), {'coin', 'crate'});

    final undo = await registry.call('undo.undo', {
      'apply': true,
    }, ctx(codec: _FakeCodec()));
    expect(undo.ok, isTrue, reason: undo.error?.message);
    expect(File(p.join(tmp.path, 'out', 'atlas.png')).existsSync(), isFalse);
  });

  test('packAtlas places non-overlapping regions', () {
    final codec = _FakeCodec();
    final items = [
      for (var i = 0; i < 5; i++) PackItem('i$i', codec.create(8 + i, 8)),
    ];
    final packed = packAtlas(codec, items, padding: 2, maxWidth: 64);
    expect(packed.regions.length, 5);
    final rects = packed.regions.values.toList();
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        final a = rects[i], b = rects[j];
        final overlap =
            a.x < b.x + b.w &&
            a.x + a.w > b.x &&
            a.y < b.y + b.h &&
            a.y + a.h > b.y;
        expect(overlap, isFalse, reason: 'regions $i and $j overlap');
      }
    }
  });

  test('tieredAtlasPath and defaultManifestPath', () {
    expect(tieredAtlasPath('assets/atlas.png', 1.0), 'assets/atlas.png');
    expect(tieredAtlasPath('assets/atlas.png', 0.5), 'assets/atlas@0.5x.png');
    expect(defaultManifestPath('assets/packed/atlas.png'), 'assets/packed/atlas.json');
  });
}
