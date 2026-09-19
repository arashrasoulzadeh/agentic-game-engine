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

  test('AnimationClip.sequence returns the same cached instance for identical arguments', () {
    final a = AnimationClip.sequence('run', 'run', 5, frameDurationSeconds: 0.12, loop: false);
    final b = AnimationClip.sequence('run', 'run', 5, frameDurationSeconds: 0.12, loop: false);

    expect(identical(a, b), isTrue);
  });

  test('AnimationClip.sequence with a different argument returns a distinct instance', () {
    final base = AnimationClip.sequence('dodge', 'dodge', 4);
    final differentName = AnimationClip.sequence('dodgeAlt', 'dodge', 4);
    final differentPrefix = AnimationClip.sequence('dodge', 'dodgeAlt', 4);
    final differentCount = AnimationClip.sequence('dodge', 'dodge', 5);
    final differentDuration =
        AnimationClip.sequence('dodge', 'dodge', 4, frameDurationSeconds: 0.2);
    final differentLoop = AnimationClip.sequence('dodge', 'dodge', 4, loop: false);
    final differentOffsets =
        AnimationClip.sequence('dodge', 'dodge', 4, frameOffsetsY: [0, 1, 2, 3]);

    for (final other in [
      differentName,
      differentPrefix,
      differentCount,
      differentDuration,
      differentLoop,
      differentOffsets,
    ]) {
      expect(identical(base, other), isFalse);
    }
  });

  test('AnimationClip.sequence forwards per-frame offsets', () {
    final clip = AnimationClip.sequence(
      'walk',
      'walk',
      3,
      frameOffsetsX: [1, 2, 3],
      frameOffsetsY: [-4, -5, -6],
    );
    expect(clip.frameOffsetsX, [1, 2, 3]);
    expect(clip.frameOffsetsY, [-4, -5, -6]);
  });

  test('AnimationClip rejects a frameOffsetsY that doesn\'t match frameRegions length', () {
    expect(
      () => AnimationClip('walk', ['a', 'b', 'c'], frameOffsetsY: [1, 2]),
      throwsA(isA<AssertionError>()),
    );
  });

  test('AnimationClip round-trips frameOffsetsX/frameOffsetsY through toJson/fromJson', () {
    final clip = AnimationClip(
      'walk',
      ['a', 'b'],
      frameOffsetsX: [1, 2],
      frameOffsetsY: [3, 4],
    );
    final restored = AnimationClip.fromJson(clip.toJson());
    expect(restored.frameOffsetsX, [1, 2]);
    expect(restored.frameOffsetsY, [3, 4]);
  });

  test('AnimationClip.toJson omits frameOffsetsX/Y when unset', () {
    final json = AnimationClip('idle', ['a']).toJson();
    expect(json.containsKey('frameOffsetsX'), isFalse);
    expect(json.containsKey('frameOffsetsY'), isFalse);
  });
}
