import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_idle/zarvan_idle.dart';

void main() {
  test('only the optional walk clip loops; idle is the rest state', () {
    final meta = FighterMeta(
      id: 'h',
      name: 'H',
      stats: FighterStats(hp: 1, attack: 1, attackSpeed: 1, armor: 0),
      stemPrefix: 'x',
      frames: {'idle': 4, 'attack': 6, 'death': 5, 'walk': 6},
    );
    final clips = meta.extraClips();
    expect(clips['walk']!.loop, isTrue);
    expect(clips['walk']!.frames, 6);
    expect(clips['attack']!.loop, isFalse);
    expect(clips.containsKey('idle'), isFalse);
    expect(FighterMeta.optionalStates, ['walk']);
  });
}
