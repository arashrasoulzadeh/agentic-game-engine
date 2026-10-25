import 'dart:convert';
import 'dart:typed_data';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

const lv = 'assets/levels/level1.json';

class _RenderImage implements EngineImage {
  _RenderImage(this.width, this.height);
  @override
  final int width;
  @override
  final int height;
}

class _RenderCodec implements ImageCodec {
  @override
  EngineImage? decode(Uint8List bytes) => null;

  @override
  EngineImage resize(EngineImage source, double scale) => source;

  @override
  EngineImage create(int width, int height) => _RenderImage(width, height);

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
  }) {}

  @override
  Uint8List encodePng(EngineImage image) {
    final i = image as _RenderImage;
    return Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, i.width, i.height]);
  }
}

void main() {
  test(
    'a loadable level lints ok; a broken one reports the problem instead of failing the call',
    () async {
      final s = await Scratch.create();
      final ok = await s.map('level.lint', {'path': lv});
      expect(ok['ok'], isTrue);
      expect(ok['message'], 'OK (3 entities)');
      s.write('assets/levels/shape.json', '{"entities": 5}');
      final bad = await s.map('level.lint', {
        'path': 'assets/levels/shape.json',
      });
      expect(bad['ok'], isFalse);
      expect(bad['problems'], isNotEmpty);
      s.write('assets/levels/notjson.json', '{nope');
      expect(
        (await s.map('level.lint', {
          'path': 'assets/levels/notjson.json',
        }))['ok'],
        isFalse,
      );
    },
  );

  test('playable passes when everything is reachable from the spawn', () async {
    final s = await Scratch.create();
    final r = await s.map('level.lint', {'path': lv, 'playable': true});
    expect(r['ok'], isTrue, reason: '$r');
    expect(r['message'], contains('reachable'));
    expect(r['unreachable'], isEmpty);
  });

  test('playable names entities that cannot be reached', () async {
    final s = await Scratch.create();
    await s.data('level.move_entity', {
      'path': lv,
      'name': 'coin_1',
      'x': 40,
      'y': 24,
    });
    final r = await s.map('level.lint', {'path': lv, 'playable': true});
    expect(r['ok'], isFalse);
    expect(r['unreachable'], ['coin_1']);
  });

  test('playable needs a tileMap and a spawn', () async {
    final s = await Scratch.create();
    s.write(
      'assets/levels/nomap.json',
      '{"entities":[{"name":"player","components":{"position":{"x":1,"y":1}}}]}',
    );
    final noMap = await s.map('level.lint', {
      'path': 'assets/levels/nomap.json',
      'playable': true,
    });
    expect(noMap['ok'], isFalse);
    expect((noMap['problems'] as List).single, contains('tileMap'));
    await s.data('level.remove_entity', {
      'path': lv,
      'name': 'player',
      'confirmation': (await s.map('level.remove_entity', {
        'path': lv,
        'name': 'player',
      }))['confirmation'],
    });
    final noSpawn = await s.map('level.lint', {'path': lv, 'playable': true});
    expect((noSpawn['problems'] as List).single, contains('no spawn'));
  });

  test('inline json works without a path', () async {
    final s = await Scratch.create();
    final r = await s.map('level.lint', {
      'json': {'entities': []},
    });
    expect(r['ok'], isTrue);
  });

  test('includeRender without a codec adds a problem', () async {
    final s = await Scratch.create();
    final r = await s.map('level.lint', {'path': lv, 'includeRender': true});
    expect(r['ok'], isFalse);
    expect((r['problems'] as List).single, contains('ImageCodec'));
    expect(r.containsKey('pngBase64'), isFalse);
  });

  test('includeRender returns a base64 PNG preview when a codec is set', () async {
    final s = await Scratch.create();
    final ctx = OpContext(
      project: s.ctx.project,
      actor: 'test',
      imageCodec: _RenderCodec(),
    );
    final result = await s.registry.call('level.lint', {
      'path': lv,
      'includeRender': true,
    }, ctx);
    expect(result.ok, isTrue, reason: '${result.error}');
    final r = (result.data! as Map).cast<String, Object?>();
    expect(r['ok'], isTrue);
    final b64 = r['pngBase64'] as String;
    expect(base64Decode(b64).take(4), [0x89, 0x50, 0x4E, 0x47]);
    final meta = (r['render'] as Map).cast<String, Object?>();
    expect(meta['cols'], 4);
    expect(meta['rows'], 2);
    expect(meta['markers'], 2); // player + coin_1
    expect(meta['width'], 4 * levelRenderPixelsPerTile);
    expect(meta['height'], 2 * levelRenderPixelsPerTile);
  });

  test('includeRender needs a tileMap', () async {
    final s = await Scratch.create();
    final ctx = OpContext(
      project: s.ctx.project,
      actor: 'test',
      imageCodec: _RenderCodec(),
    );
    final result = await s.registry.call('level.lint', {
      'path': 'assets/levels/empty.json',
      'includeRender': true,
    }, ctx);
    final r = (result.data! as Map).cast<String, Object?>();
    expect(r['ok'], isFalse);
    expect((r['problems'] as List).single, contains('tileMap'));
  });
}
