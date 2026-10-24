import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

void _write(Directory root, String path, String contents) {
  File('${root.path}/$path')
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);
}

String _manifest(List<String> names) => jsonEncode({
  'regions': {
    for (final n in names) n: {'x': 0, 'y': 0, 'w': 8, 'h': 8},
  },
});

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('assets_logic'));
  tearDown(() => root.deleteSync(recursive: true));

  group('AssetIndex.scan', () {
    test(
      'an empty project has nothing, and no declared atlases to check against',
      () {
        final index = AssetIndex.scan(root.path);
        expect(index.atlases, isEmpty);
        expect(index.images, isEmpty);
        expect(index.declaredRegions, isNull);
      },
    );

    test('a declared atlas gets its catalog id and its sprite names', () {
      _write(
        root,
        'assets/studio_atlases.json',
        jsonEncode({
          'atlases': {
            'hero': {
              'image': 'assets/hero.png',
              'manifest': 'assets/hero.json',
            },
          },
        }),
      );
      _write(root, 'assets/hero.png', 'png');
      _write(root, 'assets/hero.json', _manifest(['walk', 'idle']));
      final index = AssetIndex.scan(root.path);
      final hero = index.atlasById('hero')!;
      expect(hero.declared, isTrue);
      expect(hero.regions, ['idle', 'walk'], reason: 'sorted');
      expect(hero.image, 'assets/hero.png');
      expect(index.declaredRegions, {
        'hero': {'idle', 'walk'},
      });
      expect(
        index.images,
        isEmpty,
        reason: 'the atlas image is not listed twice',
      );
    });

    test(
      'a freshly packed sheet (png + manifest side by side) shows up undeclared',
      () {
        _write(root, 'assets/packed/atlas.png', 'png');
        _write(root, 'assets/packed/atlas.json', _manifest(['coin']));
        final index = AssetIndex.scan(root.path);
        final atlas = index.atlases.single;
        expect(atlas.id, 'atlas');
        expect(atlas.declared, isFalse);
        expect(atlas.regions, ['coin']);
        expect(
          index.declaredRegions,
          isNull,
          reason: 'undeclared atlases are not valid references',
        );
        expect(index.images, isEmpty);
        expect(
          index.data,
          isEmpty,
          reason: 'the manifest is part of the atlas',
        );
      },
    );

    test('everything else is sorted into images, audio, data and prefabs', () {
      _write(root, 'assets/logo.png', 'x');
      _write(root, 'assets/sfx/jump.WAV', 'x');
      _write(root, 'assets/music.ogg', 'x');
      _write(root, 'assets/config/balance.json', '{}');
      _write(root, 'assets/levels/one.level.json', '{}');
      _write(root, 'assets/studio_brushes.json', '{}');
      _write(root, 'prefabs/torch.json', '{}');
      _write(root, 'assets/readme.txt', 'x');
      final index = AssetIndex.scan(root.path);
      expect(index.images, ['assets/logo.png']);
      expect(index.audio, ['assets/music.ogg', 'assets/sfx/jump.WAV']);
      expect(index.data, [
        'assets/config/balance.json',
      ], reason: 'levels and studio files are not data');
      expect(index.prefabs, ['prefabs/torch.json']);
    });

    test('a broken or region-less manifest is skipped, not fatal', () {
      _write(root, 'assets/a.png', 'x');
      _write(root, 'assets/a.json', '{ nope');
      _write(root, 'assets/b.png', 'x');
      _write(root, 'assets/b.json', '{"something": 1}');
      _write(root, 'assets/c.json', _manifest(['x'])); // no sibling image
      final index = AssetIndex.scan(root.path);
      expect(index.atlases, isEmpty);
      expect(index.images, containsAll(['assets/a.png', 'assets/b.png']));
    });

    test('a catalog entry whose manifest is missing is left out', () {
      _write(
        root,
        'assets/studio_atlases.json',
        jsonEncode({
          'atlases': {
            'ghost': {'image': 'assets/g.png', 'manifest': 'assets/g.json'},
          },
        }),
      );
      expect(AssetIndex.scan(root.path).atlases, isEmpty);
    });
  });
}
