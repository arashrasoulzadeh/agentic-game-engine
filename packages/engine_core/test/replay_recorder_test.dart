import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayRecorder', () {
    test('records frames in order with their dt', () {
      final recorder = ReplayRecorder();
      recorder.record(0.1, {'moveX': 1});
      recorder.record(0.2, {'moveX': 0, 'jump': true});

      expect(recorder.frames, hasLength(2));
      expect(recorder.frames[0].dt, 0.1);
      expect(recorder.frames[0].data, {'moveX': 1});
      expect(recorder.frames[1].dt, 0.2);
      expect(recorder.frames[1].data, {'moveX': 0, 'jump': true});
    });

    test('clear() empties the recording', () {
      final recorder = ReplayRecorder()..record(0.1, {'a': 1});
      recorder.clear();
      expect(recorder.frames, isEmpty);
    });

    test('round-trips through toJson/fromJson', () {
      final recorder = ReplayRecorder()
        ..record(0.05, {'moveX': -1})
        ..record(0.1, {'moveX': 1, 'jump': true});

      final restored = ReplayRecorder.fromJson(recorder.toJson());

      expect(restored.frames, hasLength(2));
      expect(restored.frames[0].dt, 0.05);
      expect(restored.frames[0].data, {'moveX': -1});
      expect(restored.frames[1].data, {'moveX': 1, 'jump': true});
    });
  });

  group('ReplayPlayer', () {
    test('delivers each frame once its recorded dt has elapsed', () {
      final recorder = ReplayRecorder()
        ..record(0.1, {'id': 1})
        ..record(0.1, {'id': 2});
      final player = ReplayPlayer(recorder.frames);

      final delivered = <Map<String, dynamic>>[];
      player.step(0.05, delivered.add);
      expect(delivered, isEmpty, reason: 'first frame needs 0.1s, only 0.05s elapsed');

      player.step(0.05, delivered.add);
      expect(delivered, hasLength(1));
      expect(delivered[0], {'id': 1});

      player.step(0.1, delivered.add);
      expect(delivered, hasLength(2));
      expect(delivered[1], {'id': 2});

      expect(player.isFinished, isTrue);
    });

    test('a single large dt can deliver multiple frames in one step call', () {
      final recorder = ReplayRecorder()
        ..record(0.1, {'id': 1})
        ..record(0.1, {'id': 2})
        ..record(0.1, {'id': 3});
      final player = ReplayPlayer(recorder.frames);

      final delivered = <Map<String, dynamic>>[];
      player.step(0.35, delivered.add);

      expect(delivered, hasLength(3),
          reason: 'a stalled 0.35s step should replay exactly what a live run '
              'experiencing the same stall would have produced');
      expect(player.isFinished, isTrue);
    });

    test('reset() rewinds playback so the same frames deliver again', () {
      final recorder = ReplayRecorder()..record(0.1, {'id': 1});
      final player = ReplayPlayer(recorder.frames);

      final delivered = <Map<String, dynamic>>[];
      player.step(0.1, delivered.add);
      expect(player.isFinished, isTrue);

      player.reset();
      expect(player.isFinished, isFalse);
      player.step(0.1, delivered.add);
      expect(delivered, hasLength(2));
      expect(delivered[1], {'id': 1});
    });

    test('isFinished is true for an empty recording from the start', () {
      final player = ReplayPlayer([]);
      expect(player.isFinished, isTrue);
    });
  });
}
