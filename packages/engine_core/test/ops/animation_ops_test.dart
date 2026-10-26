import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('animation.set_event writes frameEvents and is undoable', () async {
    final s = await Scratch.create();
    s.write(
      'assets/anims/attack.json',
      '{\n'
      '  "name": "attack",\n'
      '  "frameRegions": ["a0", "a1", "a2"],\n'
      '  "frameDurationSeconds": 0.06,\n'
      '  "loop": false\n'
      '}\n',
    );

    final set = await s.map('animation.set_event', {
      'path': 'assets/anims/attack.json',
      'frame': 1,
      'type': 'sfx',
      'data': {'id': 'swing'},
      'apply': true,
    });
    expect(set['clip'], 'attack');
    expect(s.read('assets/anims/attack.json'), contains('"sfx"'));
    expect(s.read('assets/anims/attack.json'), contains('"swing"'));

    final valid = await s.map('animation.validate', {
      'path': 'assets/anims/attack.json',
    });
    expect(valid['ok'], isTrue);

    await s.map('animation.set_pivot', {
      'path': 'assets/anims/attack.json',
      'frame': 1,
      'offsetY': -2,
      'apply': true,
    });
    expect(s.read('assets/anims/attack.json'), contains('frameOffsetsY'));

    await s.map('undo.undo', {'apply': true});
    expect(s.read('assets/anims/attack.json'), isNot(contains('frameOffsetsY')));
  });

  test('animation.read lists clips from a library map', () async {
    final s = await Scratch.create();
    s.write(
      'assets/anims/hero.json',
      '{\n'
      '  "idle": {"name": "idle", "frameRegions": ["i0"]},\n'
      '  "walk": {"name": "walk", "frameRegions": ["w0", "w1"]}\n'
      '}\n',
    );
    final r = await s.map('animation.read', {
      'path': 'assets/anims/hero.json',
    });
    expect(r['form'], 'map');
    expect(r['names'], ['idle', 'walk']);

    await s.map('animation.set_event', {
      'path': 'assets/anims/hero.json',
      'clip': 'walk',
      'frame': 0,
      'type': 'particle',
      'data': {'count': 4},
      'apply': true,
    });
    expect(s.read('assets/anims/hero.json'), contains('"particle"'));
  });

  test('animation.validate reports bad clips', () async {
    final s = await Scratch.create();
    s.write(
      'assets/anims/bad.json',
      '{"name": "x", "frameRegions": ["a"], "frameOffsetsY": [0, 1]}\n',
    );
    final r = await s.map('animation.validate', {
      'path': 'assets/anims/bad.json',
    });
    expect(r['ok'], isFalse);
    expect((r['clips'] as Map)['x'], isNotEmpty);
  });
}
