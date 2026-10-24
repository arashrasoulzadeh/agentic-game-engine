import 'package:test/test.dart';

import 'support.dart';

const lv = 'assets/levels/level1.json';

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
}
