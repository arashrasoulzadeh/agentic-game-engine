import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/preview/preview_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 8, 8),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(8, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

LevelDocument _level() => LevelDocument.fromJson({
  'entities': [
    {
      'name': 'map',
      'components': {
        'position': {'x': 0.0, 'y': 0.0},
        'tileMap': {
          'tileWidth': 16.0,
          'tileHeight': 16.0,
          'legend': {'.': 0, '#': 1},
          'rows': ['..', '##'],
          'atlasId': 'tiles',
        },
      },
    },
  ],
});

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('textures'));
  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets(
    'the Textures switch is off and disabled when the project declares no atlas',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PreviewView(
              document: _level(),
              running: true,
              projectRoot: dir.path,
            ),
          ),
        ),
      );
      await tester.pump();

      final switcher = tester.widget<Switch>(find.byKey(const Key('textures')));
      expect(switcher.onChanged, isNull);
      expect(find.text('Textures (none declared)'), findsOneWidget);
    },
  );

  testWidgets('the Textures switch is enabled once a declared atlas has loaded', (
    tester,
  ) async {
    Directory('${dir.path}/assets').createSync();
    final bytes = await tester.runAsync(_png);
    File('${dir.path}/assets/sheet.png').writeAsBytesSync(bytes!);
    File('${dir.path}/assets/sheet.json').writeAsStringSync(
      '{"regions": {"stone": {"x": 0, "y": 0, "w": 8, "h": 8}}}',
    );
    File('${dir.path}/assets/studio_atlases.json').writeAsStringSync(
      '{"atlases": {"tiles": {"image": "assets/sheet.png", "manifest": "assets/sheet.json"}}}',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PreviewView(
            document: _level(),
            running: true,
            projectRoot: dir.path,
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();

    final switcher = tester.widget<Switch>(find.byKey(const Key('textures')));
    expect(switcher.onChanged, isNotNull);
    expect(switcher.value, isTrue);
  });
}
