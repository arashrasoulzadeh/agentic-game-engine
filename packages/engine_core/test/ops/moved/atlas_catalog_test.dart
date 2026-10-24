import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';
import 'package:test/test.dart';

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
}
