import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:zarvan_cli/src/build_pack.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('bpack'));
  tearDown(() => dir.deleteSync(recursive: true));

  void config(Map<String, Object?> json) {
    Directory('${dir.path}/assets').createSync();
    File('${dir.path}/assets/game_config.json').writeAsStringSync(
      '{"worldWidth":1,"worldHeight":1,${json.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}',
    );
  }

  test('does nothing for a project without packing configured', () async {
    config({});
    expect(await packConfiguredAtlas(dir.path), isNull);
    expect(await packConfiguredAtlas('${dir.path}/missing'), isNull);
  });

  test('a dry run reports the step and writes nothing', () async {
    config({
      'packedAtlasSource': 'art',
      'packedAtlasImage': 'assets/atlas.png',
    });
    final logs = <String>[];
    expect(await packConfiguredAtlas(dir.path, dryRun: true, log: logs.add), 0);
    expect(logs.single, contains('Would pack art'));
    expect(File('${dir.path}/assets/atlas.png').existsSync(), isFalse);
  });

  test(
    'packs the source images into the configured atlas and manifest',
    () async {
      config({
        'packedAtlasSource': 'art',
        'packedAtlasImage': 'assets/atlas.png',
        'packedAtlasManifest': 'assets/atlas.json',
      });
      Directory('${dir.path}/art').createSync();
      for (final n in ['a', 'b']) {
        File('${dir.path}/art/$n.png').writeAsBytesSync(
          img.encodePng(
            img.Image(width: 8, height: 8)..clear(img.ColorRgb8(200, 0, 0)),
          ),
        );
      }
      final logs = <String>[];
      expect(await packConfiguredAtlas(dir.path, log: logs.add), 0);
      expect(File('${dir.path}/assets/atlas.png').existsSync(), isTrue);
      final manifest = File('${dir.path}/assets/atlas.json').readAsStringSync();
      expect(manifest, allOf(contains('"a"'), contains('"b"')));
    },
  );
}
