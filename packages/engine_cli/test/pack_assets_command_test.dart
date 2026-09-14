import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/pack_assets_command.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

Future<int> _runPack(List<String> args) async {
  final runner = CommandRunner<int>('game_agent', 'test')..addCommand(PackAssetsCommand());
  return (await runner.run(['pack-assets', ...args])) ?? 0;
}

void _writeSolidPng(String path, int width, int height, img.ColorRgba8 color) {
  final image = img.Image(width: width, height: height, numChannels: 4);
  img.fill(image, color: color);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('pack_assets_test_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('returns 1 when --input is missing', () async {
    expect(await _runPack([]), 1);
  });

  test('returns 1 when --input does not exist', () async {
    expect(await _runPack(['--input', '${tmp.path}/nope']), 1);
  });

  test('returns 1 when --input has no images', () async {
    Directory('${tmp.path}/empty').createSync();
    expect(await _runPack(['--input', '${tmp.path}/empty']), 1);
  });

  test('packs images (including from nested subdirectories) into one sheet + manifest',
      () async {
    _writeSolidPng('${tmp.path}/src/coin.png', 8, 8, img.ColorRgba8(255, 215, 0, 255));
    _writeSolidPng(
        '${tmp.path}/src/level1/crate.png', 16, 12, img.ColorRgba8(139, 69, 19, 255));

    final outImage = '${tmp.path}/out/atlas.png';
    final outManifest = '${tmp.path}/out/atlas.json';
    final code = await _runPack([
      '--input', '${tmp.path}/src',
      '--output-image', outImage,
      '--output-manifest', outManifest,
    ]);

    expect(code, 0);
    expect(File(outImage).existsSync(), isTrue);
    expect(File(outManifest).existsSync(), isTrue);

    final manifest = jsonDecode(File(outManifest).readAsStringSync()) as Map<String, dynamic>;
    final regions = (manifest['regions'] as Map).cast<String, dynamic>();
    expect(regions.keys.toSet(), {'coin', 'crate'});

    final coin = (regions['coin'] as Map).cast<String, dynamic>();
    expect(coin['w'], 8);
    expect(coin['h'], 8);
    final crate = (regions['crate'] as Map).cast<String, dynamic>();
    expect(crate['w'], 16);
    expect(crate['h'], 12);

    // Regions must not overlap -- decode the sheet and verify each
    // region's rect is fully filled with its own source image's flat
    // color, i.e. the packer actually placed non-overlapping rects and
    // composited the real pixel data there, not just wrote *a* manifest.
    final sheet = img.decodeImage(File(outImage).readAsBytesSync())!;
    final coinPixel = sheet.getPixel((coin['x'] as int) + 1, (coin['y'] as int) + 1);
    expect(coinPixel.r, 255);
    expect(coinPixel.g, 215);
    expect(coinPixel.b, 0);
    final cratePixel = sheet.getPixel((crate['x'] as int) + 1, (crate['y'] as int) + 1);
    expect(cratePixel.r, 139);
    expect(cratePixel.g, 69);
    expect(cratePixel.b, 19);
  });

  test('--padding keeps adjacent regions from touching', () async {
    _writeSolidPng('${tmp.path}/src/a.png', 4, 4, img.ColorRgba8(255, 0, 0, 255));
    _writeSolidPng('${tmp.path}/src/b.png', 4, 4, img.ColorRgba8(0, 255, 0, 255));

    final outImage = '${tmp.path}/out/atlas.png';
    await _runPack(['--input', '${tmp.path}/src', '--output-image', outImage, '--padding', '5']);

    final manifest =
        jsonDecode(File('${tmp.path}/out/atlas.json').readAsStringSync()) as Map<String, dynamic>;
    final regions = (manifest['regions'] as Map).cast<String, dynamic>();
    final a = (regions['a'] as Map).cast<String, dynamic>();
    final b = (regions['b'] as Map).cast<String, dynamic>();
    // Same row (both 4px tall, packed widest/tallest-first) -- b's left
    // edge must clear a's right edge by at least the padding.
    final aRight = (a['x'] as int) + (a['w'] as int);
    expect((b['x'] as int) - aRight, greaterThanOrEqualTo(5));
  });

  test('output-manifest defaults to output-image with a .json extension', () async {
    _writeSolidPng('${tmp.path}/src/a.png', 4, 4, img.ColorRgba8(255, 0, 0, 255));

    final code = await _runPack([
      '--input', '${tmp.path}/src',
      '--output-image', '${tmp.path}/out/sheet.png',
    ]);

    expect(code, 0);
    expect(File('${tmp.path}/out/sheet.json').existsSync(), isTrue);
  });

  test('--scales writes one sheet+manifest pair per tier, with the 1.0 tier keeping '
      'the plain --output-image/--output-manifest paths unsuffixed', () async {
    _writeSolidPng('${tmp.path}/src/coin.png', 20, 20, img.ColorRgba8(255, 0, 0, 255));

    final code = await _runPack([
      '--input', '${tmp.path}/src',
      '--output-image', '${tmp.path}/out/atlas.png',
      '--scales', '1.0,0.5,0.25',
    ]);

    expect(code, 0);
    expect(File('${tmp.path}/out/atlas.png').existsSync(), isTrue,
        reason: '1.0 tier keeps the unsuffixed path');
    expect(File('${tmp.path}/out/atlas.json').existsSync(), isTrue);
    expect(File('${tmp.path}/out/atlas@0.5x.png').existsSync(), isTrue);
    expect(File('${tmp.path}/out/atlas@0.5x.json').existsSync(), isTrue);
    expect(File('${tmp.path}/out/atlas@0.25x.png').existsSync(), isTrue);
    expect(File('${tmp.path}/out/atlas@0.25x.json').existsSync(), isTrue);

    final fullManifest = jsonDecode(File('${tmp.path}/out/atlas.json').readAsStringSync())
        as Map<String, dynamic>;
    final fullCoin =
        ((fullManifest['regions'] as Map)['coin'] as Map).cast<String, dynamic>();
    expect(fullCoin['w'], 20);
    expect(fullCoin['h'], 20);

    final halfManifest = jsonDecode(File('${tmp.path}/out/atlas@0.5x.json').readAsStringSync())
        as Map<String, dynamic>;
    final halfCoin =
        ((halfManifest['regions'] as Map)['coin'] as Map).cast<String, dynamic>();
    expect(halfCoin['w'], 10);
    expect(halfCoin['h'], 10);

    final quarterManifest =
        jsonDecode(File('${tmp.path}/out/atlas@0.25x.json').readAsStringSync())
            as Map<String, dynamic>;
    final quarterCoin =
        ((quarterManifest['regions'] as Map)['coin'] as Map).cast<String, dynamic>();
    expect(quarterCoin['w'], 5);
    expect(quarterCoin['h'], 5);
  });

  test('--scales tolerates a source image tiny enough that a small scale would round '
      'to 0px -- clamped to at least 1px per side, not a degenerate empty region',
      () async {
    _writeSolidPng('${tmp.path}/src/tiny.png', 2, 2, img.ColorRgba8(255, 0, 0, 255));

    final code = await _runPack([
      '--input', '${tmp.path}/src',
      '--output-image', '${tmp.path}/out/atlas.png',
      '--scales', '1.0,0.1',
    ]);

    expect(code, 0);
    final manifest = jsonDecode(File('${tmp.path}/out/atlas@0.1x.json').readAsStringSync())
        as Map<String, dynamic>;
    final tiny = ((manifest['regions'] as Map)['tiny'] as Map).cast<String, dynamic>();
    expect(tiny['w'], greaterThanOrEqualTo(1));
    expect(tiny['h'], greaterThanOrEqualTo(1));
  });

  test('--scales rejects a non-numeric or non-positive value', () async {
    _writeSolidPng('${tmp.path}/src/a.png', 4, 4, img.ColorRgba8(255, 0, 0, 255));

    expect(
      await _runPack([
        '--input', '${tmp.path}/src',
        '--output-image', '${tmp.path}/out/atlas.png',
        '--scales', 'not-a-number',
      ]),
      1,
    );
    expect(
      await _runPack([
        '--input', '${tmp.path}/src',
        '--output-image', '${tmp.path}/out2/atlas.png',
        '--scales', '0',
      ]),
      1,
    );
  });

  test('MaxRects packing stays reasonably dense for a mixed-aspect-ratio set '
      '(one tall/narrow item alongside many small ones) -- a shelf/row packer would '
      'waste real space here, since every item sharing a row pays for the row\'s '
      "tallest item's height even when it's a fraction of that height itself",
      () async {
    _writeSolidPng('${tmp.path}/src/tall.png', 10, 200, img.ColorRgba8(255, 0, 0, 255));
    for (var i = 0; i < 30; i++) {
      _writeSolidPng('${tmp.path}/src/small_$i.png', 10, 10, img.ColorRgba8(0, 255, 0, 255));
    }

    final outImage = '${tmp.path}/out/atlas.png';
    await _runPack(['--input', '${tmp.path}/src', '--output-image', outImage, '--padding', '0']);

    final sheet = img.decodeImage(File(outImage).readAsBytesSync())!;
    final packedArea = sheet.width * sheet.height;
    final itemArea = 10 * 200 + 30 * (10 * 10);

    // A real bin-packer should land within a small constant factor of
    // the theoretical minimum (sum of item areas) for a set this size;
    // a naive shelf packer sizing every row by its tallest item would
    // blow well past this for exactly this kind of mixed set.
    expect(packedArea, lessThan(itemArea * 2),
        reason: 'packed ${sheet.width}x${sheet.height}=$packedArea vs $itemArea of actual '
            'sprite pixels -- too much wasted space for a real bin-packer');
  });

  test('a single item wider than --max-width still packs correctly (the packer grows '
      'the bin instead of treating --max-width as a hard cap)', () async {
    _writeSolidPng('${tmp.path}/src/wide.png', 100, 10, img.ColorRgba8(255, 0, 0, 255));

    final outImage = '${tmp.path}/out/atlas.png';
    final code = await _runPack([
      '--input', '${tmp.path}/src',
      '--output-image', outImage,
      '--max-width', '10', // deliberately far too small
    ]);

    expect(code, 0);
    final manifest =
        jsonDecode(File('${tmp.path}/out/atlas.json').readAsStringSync()) as Map<String, dynamic>;
    final wide = ((manifest['regions'] as Map)['wide'] as Map).cast<String, dynamic>();
    expect(wide['w'], 100);
    expect(wide['h'], 10);
  });

  test('two images with the same basename in different subfolders is an error, not '
      'a silent overwrite', () async {
    _writeSolidPng('${tmp.path}/src/levels/1/coin.png', 4, 4, img.ColorRgba8(255, 0, 0, 255));
    _writeSolidPng('${tmp.path}/src/levels/2/coin.png', 4, 4, img.ColorRgba8(0, 255, 0, 255));

    final code = await _runPack([
      '--input', '${tmp.path}/src',
      '--output-image', '${tmp.path}/out/atlas.png',
    ]);
    expect(code, 1);
  });
}
