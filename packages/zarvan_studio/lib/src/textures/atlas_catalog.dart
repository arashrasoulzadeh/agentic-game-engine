import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:zarvan_core/zarvan_core_ops.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart';
import 'package:path/path.dart' as p;

export 'package:zarvan_core/zarvan_core_ops.dart'
    show AtlasCatalog, AtlasEntry, atlasCatalogFile;

/// Decoding the declared atlases needs `dart:ui`, so it stays in the studio; the catalog data itself
/// (`AtlasCatalog`) lives in `zarvan_core` where the operation registry can read it.
extension AtlasCatalogLoad on AtlasCatalog {
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
