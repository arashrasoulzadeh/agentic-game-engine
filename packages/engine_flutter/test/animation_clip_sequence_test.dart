import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AnimationClip.sequence generates prefix_N region names', () {
    final clip = AnimationClip.sequence('walk', 'walk', 4);
    expect(clip.name, 'walk');
    expect(clip.frameRegions, ['walk_0', 'walk_1', 'walk_2', 'walk_3']);
  });

  test('AnimationClip.sequence forwards duration/loop', () {
    final clip = AnimationClip.sequence(
      'jump',
      'jump',
      3,
      frameDurationSeconds: 0.08,
      loop: false,
    );
    expect(clip.frameDurationSeconds, 0.08);
    expect(clip.loop, isFalse);
    expect(clip.frameRegions, ['jump_0', 'jump_1', 'jump_2']);
  });
}
