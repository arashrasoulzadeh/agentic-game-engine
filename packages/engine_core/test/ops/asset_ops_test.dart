import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test(
    'index sorts files, finds a packed atlas next to its image and a declared one',
    () async {
      final s = await Scratch.create();
      s.write('assets/hero.png', 'png');
      s.write(
        'assets/hero.json',
        '{"regions": {"idle": {"x": 0, "y": 0, "w": 16, "h": 16}, "run": {"x": 16, "y": 0, "w": 16, "h": 16}}}',
      );
      s.write('assets/loose.png', 'png');
      s.write('assets/sfx/jump.wav', 'wav');
      s.write('assets/tiles.png', 'png');
      s.write(
        'assets/tiles_manifest.json',
        '{"regions": {"grass": {"x": 0, "y": 0, "w": 8, "h": 8}}}',
      );
      s.write(
        'assets/studio_atlases.json',
        '{"atlases": {"terrain": {"image": "assets/tiles.png", "manifest": "assets/tiles_manifest.json"}}}',
      );
      final d = await s.map('asset.index');
      final atlases = {
        for (final a in d['atlases']! as List) (a as Map)['id']: a,
      };
      expect(atlases.keys, containsAll(['hero', 'terrain']));
      expect(atlases['terrain']!['declared'], isTrue);
      expect(atlases['hero']!['declared'], isFalse);
      expect(atlases['hero']!['regions'], 2);
      expect(d['images'], [
        'assets/loose.png',
      ], reason: 'atlas images are not repeated');
      expect(d['audio'], ['assets/sfx/jump.wav']);
    },
  );

  test(
    'atlas_regions returns the manifest rectangles in name order; unknown atlas is not_found',
    () async {
      final s = await Scratch.create();
      s.write('assets/hero.png', 'png');
      s.write(
        'assets/hero.json',
        '{"regions": {"run": {"x": 16, "y": 0, "w": 16, "h": 16}, "idle": {"x": 0, "y": 0, "w": 16, "h": 16}}}',
      );
      final r = await s.map('asset.atlas_regions', {'atlas': 'hero'});
      expect((r['regions']! as Map).keys, ['idle', 'run']);
      expect(((r['regions']! as Map)['run'] as Map)['x'], 16);
      expect(r['image'], 'assets/hero.png');
      expect(
        await s.failure('asset.atlas_regions', {'atlas': 'nope'}),
        ErrorCode.notFound,
      );
    },
  );

  test('an empty project has nothing to list', () async {
    final s = await Scratch.create();
    final d = await s.map('asset.index');
    expect(d['atlases'], isEmpty);
    expect(d['images'], isEmpty);
  });
}
