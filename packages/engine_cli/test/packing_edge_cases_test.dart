import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/command_runner.dart';
import 'package:engine_cli/src/pack_assets_command.dart';
import 'package:image/image.dart' as img;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('packing_edges_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  void writeImage(String name, int w, int h, int red) {
    final image = img.Image(width: w, height: h, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(red, 33, 77, 255));
    File('${tmp.path}/src/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodePng(image));
  }

  Future<int?> run({int attempts = 20, String scales = '1'}) =>
      (CommandRunner<int>('game_agent', 'test')
        ..addCommand(PackAssetsCommand(maxPackingAttempts: attempts)))
      .run(['pack-assets', '--input', '${tmp.path}/src',
        '--output-image', '${tmp.path}/out/atlas.png', '--max-width', '1',
        '--padding', '0', '--scales', scales]);

  test('packing retries grow a bin that cannot hold two squares initially', () async {
    writeImage('a', 10, 10, 40);
    writeImage('b', 10, 10, 80);
    await expectLater(run(attempts: 1), throwsA(isA<StateError>().having(
      (e) => e.message, 'message', contains('after 1 grow attempts'))));
    expect(File('${tmp.path}/out/atlas.png').existsSync(), isFalse);
    expect(await run(scales: '2'), 0);
    final doubled = jsonDecode(File('${tmp.path}/out/atlas@2x.json').readAsStringSync()) as Map;
    expect(doubled['regions']['a']['w'], 20);
    expect(doubled['regions']['b']['h'], 20);
  });

  test('mixed shapes remain disjoint and retain their pixels after free-space splitting', () async {
    final random = Random(901);
    final dimensions = <String, (int, int, int)>{};
    for (var i = 0; i < 40; i++) {
      final name = 'item_$i';
      final w = 2 + random.nextInt(35), h = 2 + random.nextInt(35);
      dimensions[name] = (w, h, i + 20);
      writeImage(name, w, h, i + 20);
    }
    expect(await run(), 0);
    final file = File('${tmp.path}/out/atlas.json');
    final originalManifest = file.readAsStringSync();
    final regions = (jsonDecode(originalManifest)['regions'] as Map).cast<String, dynamic>();
    final sheet = img.decodePng(File('${tmp.path}/out/atlas.png').readAsBytesSync())!;
    expect(regions.keys, unorderedEquals(dimensions.keys));
    final rectangles = <Rectangle<int>>[];
    for (final entry in regions.entries) {
      final data = entry.value as Map;
      final rect = Rectangle<int>(data['x'] as int, data['y'] as int, data['w'] as int, data['h'] as int);
      final (w, h, red) = dimensions[entry.key]!;
      expect((rect.width, rect.height), (w, h));
      expect(rect.right, lessThanOrEqualTo(sheet.width));
      expect(rect.bottom, lessThanOrEqualTo(sheet.height));
      for (final other in rectangles) {
        final intersection = rect.intersection(other);
        expect(intersection == null || intersection.width * intersection.height == 0, isTrue);
      }
      for (var y = rect.top; y < rect.bottom; y++) {
        for (var x = rect.left; x < rect.right; x++) {
          expect(sheet.getPixel(x, y).r, red);
        }
      }
      rectangles.add(rect);
    }
    expect(await run(), 0);
    expect(file.readAsStringSync(), originalManifest);
  });
}
