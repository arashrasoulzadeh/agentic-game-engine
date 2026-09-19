import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayFrame', () {
    test('round-trips through toJson/fromJson', () {
      final frame = ReplayFrame(0.016, {'action': 'jump', 'value': 42});
      final json = frame.toJson();
      final restored = ReplayFrame.fromJson(json);

      expect(restored.dt, 0.016);
      expect(restored.data['action'], 'jump');
      expect(restored.data['value'], 42);
    });
  });

  group('ReplayRecorder', () {
    test('records frames with dt and data', () {
      final recorder = ReplayRecorder();
      recorder.record(0.016, {'input': 'left'});
      recorder.record(0.016, {'input': 'jump'});

      expect(recorder.frames.length, 2);
      expect(recorder.frames[0].dt, 0.016);
      expect(recorder.frames[0].data['input'], 'left');
      expect(recorder.frames[1].data['input'], 'jump');
    });

    test('clear removes all frames', () {
      final recorder = ReplayRecorder();
      recorder.record(0.016, {'a': 1});
      recorder.clear();
      expect(recorder.frames, isEmpty);
    });

    test('toJson serializes all frames', () {
      final recorder = ReplayRecorder();
      recorder.record(0.01, {'a': 1});
      recorder.record(0.02, {'b': 2});

      final json = recorder.toJson();
      expect(json.length, 2);
      expect(json[0]['dt'], 0.01);
      expect(json[0]['data']['a'], 1);
      expect(json[1]['dt'], 0.02);
      expect(json[1]['data']['b'], 2);
    });

    test('fromJson deserializes frames', () {
      final json = [
        {'dt': 0.016, 'data': {'action': 'left'}},
        {'dt': 0.016, 'data': {'action': 'right'}},
      ];
      final recorder = ReplayRecorder.fromJson(json);

      expect(recorder.frames.length, 2);
      expect(recorder.frames[0].dt, 0.016);
      expect(recorder.frames[0].data['action'], 'left');
      expect(recorder.frames[1].data['action'], 'right');
    });

    test('round-trips through toJson/fromJson', () {
      final recorder = ReplayRecorder();
      recorder.record(0.01, {'a': 1});
      recorder.record(0.02, {'b': 2});

      final json = recorder.toJson();
      final restored = ReplayRecorder.fromJson(json);

      expect(restored.frames.length, 2);
      expect(restored.frames[0].dt, 0.01);
      expect(restored.frames[1].dt, 0.02);
    });
  });

  group('ReplayPlayer', () {
    test('plays back frames at correct timing', () {
      final frames = [
        ReplayFrame(0.016, {'frame': 1}),
        ReplayFrame(0.016, {'frame': 2}),
        ReplayFrame(0.016, {'frame': 3}),
      ];
      final player = ReplayPlayer(frames);

      final received = <Map<String, dynamic>>[];
      player.step(0.016, (data) => received.add(data));
      expect(received.length, 1);
      expect(received[0]['frame'], 1);

      player.step(0.016, (data) => received.add(data));
      expect(received.length, 2);
      expect(received[1]['frame'], 2);

      player.step(0.016, (data) => received.add(data));
      expect(received.length, 3);
      expect(received[2]['frame'], 3);
      expect(player.isFinished, isTrue);
    });

    test('delivers multiple frames if dt exceeds frame time', () {
      final frames = [
        ReplayFrame(0.01, {'frame': 1}),
        ReplayFrame(0.01, {'frame': 2}),
        ReplayFrame(0.01, {'frame': 3}),
      ];
      final player = ReplayPlayer(frames);

      final received = <int>[];
      player.step(0.025, (data) => received.add(data['frame'] as int));
      // 0.025 > 0.01 + 0.01, so should deliver first two frames
      expect(received, [1, 2]);
      expect(player.isFinished, isFalse);
    });

    test('reset rewinds to start', () {
      final frames = [ReplayFrame(0.016, {'frame': 1})];
      final player = ReplayPlayer(frames);

      player.step(0.016, (_) {});
      expect(player.isFinished, isTrue);

      player.reset();
      expect(player.isFinished, isFalse);

      final received = <int>[];
      player.step(0.016, (data) => received.add(data['frame'] as int));
      expect(received, [1]);
    });

    test('large dt delivers all remaining frames', () {
      final frames = [
        ReplayFrame(0.01, {'f': 1}),
        ReplayFrame(0.01, {'f': 2}),
        ReplayFrame(0.01, {'f': 3}),
      ];
      final player = ReplayPlayer(frames);

      final received = <int>[];
      player.step(1.0, (data) => received.add(data['f'] as int));
      expect(received, [1, 2, 3]);
      expect(player.isFinished, isTrue);
    });

    test('empty frames finishes immediately', () {
      final player = ReplayPlayer([]);
      expect(player.isFinished, isTrue);
    });
  });
}