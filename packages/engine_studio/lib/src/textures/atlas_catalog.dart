import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:engine_flutter/engine_flutter.dart';
import 'package:path/path.dart' as p;

/// Where a project keeps its atlas list, relative to the project root.
const atlasCatalogFile = 'assets/studio_atlases.json';

/// One atlas a project declares: the sprite sheet image and its region manifest,
/// both relative to the project root.
class AtlasEntry {
  final String image;
  final String manifest;

  const AtlasEntry({required this.image, required this.manifest});
}

/// The atlases a project's art lives in, by the id its levels use (`atlasId`).
///
/// The studio cannot read the game's Dart code to learn which file an id means,
/// so the project declares the mapping in `assets/studio_atlases.json`:
/// `{"atlases": {"prisonTiles": {"image": "assets/x.png", "manifest": "assets/x_manifest.json"}}}`.
class AtlasCatalog {
  final Map<String, AtlasEntry> entries;

  const AtlasCatalog(this.entries);

  /// Reads the catalog from [projectRoot]. A missing file means no textures, not an
  /// error: the preview then draws plain shapes.
  factory AtlasCatalog.read(String projectRoot) {
    final file = File(p.join(projectRoot, atlasCatalogFile));
    if (!file.existsSync()) return const AtlasCatalog({});
    return AtlasCatalog.parse(file.readAsStringSync());
  }

  /// Parses catalog JSON. Entries missing an image or manifest are skipped, so one
  /// bad line does not hide the rest.
  factory AtlasCatalog.parse(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    final atlases =
        (decoded['atlases'] as Map?)?.cast<String, dynamic>() ?? const {};
    final entries = <String, AtlasEntry>{};
    atlases.forEach((id, value) {
      if (value is Map &&
          value['image'] is String &&
          value['manifest'] is String) {
        entries[id] = AtlasEntry(
          image: value['image'] as String,
          manifest: value['manifest'] as String,
        );
      }
    });
    return AtlasCatalog(entries);
  }

  /// Decodes every declared atlas from [projectRoot]. An atlas whose files cannot be
  /// read is left out, so the preview falls back to shapes for it.
  Future<Map<String, SpriteAtlas>> load(String projectRoot) async {
    final loaded = <String, SpriteAtlas>{};
    for (final entry in entries.entries) {
      try {
        final bytes = File(
          p.join(projectRoot, entry.value.image),
        ).readAsBytesSync();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final manifest =
            jsonDecode(
                  File(
                    p.join(projectRoot, entry.value.manifest),
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        loaded[entry.key] = SpriteAtlas.fromManifest(frame.image, manifest);
      } on Object {
        continue;
      }
    }
    return loaded;
  }
}
