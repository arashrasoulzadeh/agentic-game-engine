import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> clip() => {
        'name': 'attack',
        'frameRegions': ['a0', 'a1', 'a2'],
        'frameDurationSeconds': 0.1,
        'loop': false,
      };

  test('validateAnimationClipJson accepts a minimal clip', () {
    expect(validateAnimationClipJson(clip()), isEmpty);
  });

  test('validateAnimationClipJson catches offset/event length mismatches', () {
    final bad = clip()
      ..['frameOffsetsY'] = [0.0, 1.0]
      ..['frameEvents'] = [
        [],
        [
          {'type': 'sfx'},
        ],
      ];
    final problems = validateAnimationClipJson(bad);
    expect(problems, contains(contains('frameOffsetsY length')));
    expect(problems, contains(contains('frameEvents length')));
  });

  test('parseAnimationClipLibrary handles single, map, and clips forms', () {
    expect(parseAnimationClipLibrary(clip()).keys, ['attack']);
    expect(
      parseAnimationClipLibrary({
        'idle': clip()..['name'] = 'idle',
        'walk': {
          'name': 'walk',
          'frameRegions': ['w0'],
        },
      }).keys.toList()
        ..sort(),
      ['idle', 'walk'],
    );
    expect(
      parseAnimationClipLibrary({
        'clips': [clip()],
      }).keys,
      ['attack'],
    );
  });

  test('setClipFrameEvent and setClipFramePivot mutate the clip', () {
    final c = clip();
    setClipFrameEvent(
      c,
      frameIndex: 1,
      type: 'sfx',
      data: {'id': 'swing'},
    );
    setClipFramePivot(c, frameIndex: 1, offsetY: -4);
    expect(c['frameEvents'][1], [
      {
        'type': 'sfx',
        'data': {'id': 'swing'},
      },
    ]);
    expect(c['frameOffsetsY'], [0.0, -4.0, 0.0]);
    clearClipFrameEvents(c, frameIndex: 1, type: 'sfx');
    expect(c['frameEvents'][1], isEmpty);
  });

  test('encodeAnimationClipLibrary round-trips forms', () {
    final lib = parseAnimationClipLibrary(clip());
    expect(detectAnimationLibraryForm(clip()), 'single');
    expect(isAnimationClipJson(encodeAnimationClipLibrary(lib, form: 'single')), isTrue);
    final asClips = encodeAnimationClipLibrary(lib, form: 'clips') as Map;
    expect(asClips['clips'], isA<List>());
  });
}
