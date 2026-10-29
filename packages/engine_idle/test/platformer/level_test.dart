import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('LevelData parses anchors, wave list and preview multipliers', () {
    final level = LevelData.fromJson({
      'name': 'A1',
      'wave': ['wolf', 'bat'],
      'boss': 'kakuy',
      'background': 'bg.png',
      'hero': {'x': 8, 'y': 200},
      'enemy_anchor': {'x': 100.5, 'y': 190},
      'preview_hero_scale': {'hp': 2},
      'preview_boss_scale': {'attack': 0.5},
      'parallax': [
        {'name': 'far', 'speed': 0.3, 'z': -90},
        {'name': 'near', 'speed': 1.0},
      ],
    });
    expect(level.enemyIds, ['wolf', 'bat', 'kakuy']);
    expect(level.enemyAnchor.x, 100.5);
    expect(level.scaled('hp', 10), 20);
    expect(level.scaled('attack', 10), 10);
    expect(level.gdd, '');
    expect(level.parallax.map((l) => (l.name, l.speed, l.zIndex)), [
      ('far', 0.3, -90),
      ('near', 1.0, -100),
    ]);
    expect(level.bossScaled('attack', 20), 10);
    expect(level.bossScaled('hp', 20), 20);
  });

  test('WaveProgress walks the wave then the boss', () {
    final w = WaveProgress(wave: ['a', 'b'], boss: 'k');
    expect((w.currentId, w.label, w.isBoss), ('a', 'Wave 1/2', false));
    w.advance();
    expect(w.currentId, 'b');
    w.advance();
    expect((w.currentId, w.isBoss), ('k', true));
  });
}
