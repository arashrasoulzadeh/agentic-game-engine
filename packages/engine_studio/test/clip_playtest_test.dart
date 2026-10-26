import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_studio/src/animation/clip_editor_screen.dart';
import 'package:engine_studio/src/animation/clip_playtest.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 16, 8),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  final image = await recorder.endRecording().toImage(16, 8);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

void main() {
  late Directory dir;
  late String clipPath;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('clip_playtest');
    Directory('${dir.path}/assets').createSync();
    File('${dir.path}/assets/sheet.png').writeAsBytesSync(await _png());
    File('${dir.path}/assets/sheet.json').writeAsStringSync(
      jsonEncode({
        'regions': {
          'a0': {'x': 0, 'y': 0, 'w': 8, 'h': 8},
          'a1': {'x': 8, 'y': 0, 'w': 8, 'h': 8},
        },
      }),
    );
    File('${dir.path}/assets/studio_atlases.json').writeAsStringSync(
      jsonEncode({
        'atlases': {
          'hero': {
            'image': 'assets/sheet.png',
            'manifest': 'assets/sheet.json',
          },
        },
      }),
    );
    clipPath = '${dir.path}/attack.json';
    File(clipPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'name': 'attack',
        'frameRegions': ['a0', 'a1'],
        'frameDurationSeconds': 0.1,
        'loop': true,
      }),
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  testWidgets('ClipPlaytest mounts EngineView once the atlas loads', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ClipPlaytest(
              projectRoot: dir.path,
              clip: {
                'name': 'attack',
                'frameRegions': ['a0', 'a1'],
                'frameDurationSeconds': 0.1,
                'loop': true,
              },
              atlasId: 'hero',
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const Key('clip-playtest')), findsOneWidget);
  });

  testWidgets('editor exposes engine playtest toggle when projectRoot set', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClipEditorScreen(
            filePath: clipPath,
            projectRoot: dir.path,
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('clip-engine-playtest')), findsOneWidget);
    // Disabled until an atlas is chosen.
    final button = tester.widget<IconButton>(
      find.byKey(const Key('clip-engine-playtest')),
    );
    expect(button.onPressed, isNull);
  });
}
