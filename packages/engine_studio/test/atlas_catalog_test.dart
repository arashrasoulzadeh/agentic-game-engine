import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_studio/src/textures/atlas_catalog.dart';
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

void main() {
  test('parses declared atlases and skips entries missing a file', () {
    final catalog = AtlasCatalog.parse('''
{"atlases": {
  "prisonTiles": {"image": "assets/a.png", "manifest": "assets/a.json"},
  "broken": {"image": "assets/b.png"}
}}''');
    expect(catalog.entries.keys, ['prisonTiles']);
    expect(catalog.entries['prisonTiles']!.manifest, 'assets/a.json');
  });

  test('a project without a catalog has no atlases, not an error', () {
    final dir = Directory.systemTemp.createTempSync('catalog_none');
    addTearDown(() => dir.deleteSync(recursive: true));
    expect(AtlasCatalog.read(dir.path).entries, isEmpty);
  });

  test('loads a declared atlas from the project files', () async {
    final dir = Directory.systemTemp.createTempSync('catalog_load');
    addTearDown(() => dir.deleteSync(recursive: true));
    Directory('${dir.path}/assets').createSync();
    File('${dir.path}/assets/sheet.png').writeAsBytesSync(await _png());
    File('${dir.path}/assets/sheet.json').writeAsStringSync(
      '{"regions": {"stone": {"x": 0, "y": 0, "w": 4, "h": 4}}}',
    );
    File('${dir.path}/assets/studio_atlases.json').writeAsStringSync(
      '{"atlases": {"tiles": {"image": "assets/sheet.png", "manifest": "assets/sheet.json"}}}',
    );

    final atlases = await AtlasCatalog.read(dir.path).load(dir.path);
    expect(atlases.containsKey('tiles'), isTrue);
    expect(atlases['tiles']!.regions.containsKey('stone'), isTrue);
  });
}
