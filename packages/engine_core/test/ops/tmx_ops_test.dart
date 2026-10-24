import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

const lv = 'assets/levels/level1.json';

void main() {
  test('export then import round-trips the tiles and solid set', () async {
    final s = await Scratch.create();
    final out = await s.map('level.export_tmx', {'path': lv});
    expect(out['path'], 'assets/levels/level1.tmx');
    expect(out['cols'], 4);
    expect(out['lost'], isEmpty);
    expect(s.read('assets/levels/level1.tmx'), contains('<map'));

    final imp = await s.map('level.import_tmx', {
      'tmx': 'assets/levels/level1.tmx',
      'output': 'assets/levels/copy.json',
      'entity': 'floor',
    });
    expect(imp['path'], 'assets/levels/copy.json');
    final entity =
        (jsonDecode(s.read('assets/levels/copy.json'))['entities'] as List)
                .single
            as Map;
    expect(entity['name'], 'floor');
    final tileMap = (entity['components'] as Map)['tileMap'] as Map;
    expect(tileMap['tiles'], [0, 0, 0, 0, 1, 1, 1, 1]);
    expect(tileMap['solidTileIds'], [1]);
  });

  test(
    'export names what Tiled cannot hold; missing tileMap or entity is not_found',
    () async {
      final s = await Scratch.create();
      expect(
        await s.failure('level.export_tmx', {
          'path': 'assets/levels/empty.json',
        }),
        ErrorCode.notFound,
      );
      expect(
        await s.failure('level.export_tmx', {'path': lv, 'entity': 'player'}),
        ErrorCode.notFound,
      );
    },
  );

  test('import refuses an existing output and unsupported maps', () async {
    final s = await Scratch.create();
    await s.data('level.export_tmx', {'path': lv});
    expect(
      await s.failure('level.import_tmx', {
        'tmx': 'assets/levels/level1.tmx',
        'output': lv,
      }),
      ErrorCode.conflict,
    );
    s.write('assets/levels/bad.tmx', '<notamap/>');
    expect(
      await s.failure('level.import_tmx', {'tmx': 'assets/levels/bad.tmx'}),
      ErrorCode.validationFailed,
    );
    expect(
      await s.failure('level.import_tmx', {'tmx': 'assets/levels/none.tmx'}),
      ErrorCode.notFound,
    );
  });

  test(
    'no operation can write into .studio (token, undo journal) or .git',
    () async {
      final s = await Scratch.create();
      s.write('.studio/api-token', 'secret');
      for (final out in [
        '.studio/api-token',
        './.studio/undo/x.tmx',
        '.git/config',
        'assets/../.studio/y',
      ]) {
        final r = await s.call('level.export_tmx', {'path': lv, 'output': out});
        expect(
          r.error?.code,
          anyOf(ErrorCode.forbidden, ErrorCode.invalidParams),
          reason: out,
        );
      }
      expect(s.read('.studio/api-token'), 'secret');
      expect(s.exists('.git/config'), isFalse);
      expect(
        (await s.call('level.export_tmx', {
          'path': lv,
          'output': 'assets/ok.tmx',
        })).ok,
        isTrue,
      );
    },
  );
}
