import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SheetSidecar parses the grid with defaults for gap and frames', () {
    final s = SheetSidecar.fromJson({'cell': 64, 'gap': 8, 'frames': 6});
    expect((s.cell, s.gap, s.frames), (64, 8, 6));
    final d = SheetSidecar.fromJson({'cell': 32});
    expect((d.gap, d.frames), (0, 1));
  });

  test('loadFxClip reads the frame count from the sidecar json', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
          return const StringCodec().encodeMessage(
            '{"cell": 64, "gap": 8, "frames": 5}',
          );
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    final clip = await loadFxClip('fx_spark', 'assets/fx_spark');
    expect((clip.atlasId, clip.frames), ('fx_spark', 5));
  });
}
