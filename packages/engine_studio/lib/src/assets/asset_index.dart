import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../textures/atlas_catalog.dart';

/// One sprite sheet and the names of the sprites packed into it.
class AtlasInfo {
  /// The id levels use (`atlasId`), when the project declares one in
  /// `assets/studio_atlases.json`; otherwise the file's base name.
  final String id;

  /// Project-relative paths.
  final String image;
  final String manifest;

  /// Sprite names from the manifest, sorted.
  final List<String> regions;

  /// True if the project's catalog declares it (so levels can reference it by [id]).
  final bool declared;

  const AtlasInfo({
    required this.id,
    required this.image,
    required this.manifest,
    required this.regions,
    required this.declared,
  });
}

/// Everything in a project's `assets/` folder, sorted into what the studio can show.
class AssetIndex {
  final List<AtlasInfo> atlases;

  /// Image files that are not part of an atlas.
  final List<String> images;
  final List<String> audio;
  final List<String> data;

  /// `prefabs/*.json`, project-relative.
  final List<String> prefabs;

  const AssetIndex({
    required this.atlases,
    required this.images,
    required this.audio,
    required this.data,
    required this.prefabs,
  });

  static const _imageExt = ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'];
  static const _audioExt = ['.wav', '.mp3', '.ogg', '.m4a', '.flac'];

  /// Scans [projectRoot]. Atlases come from two places: the project's catalog (which
  /// gives them an id), and any `X.json` with a `regions` map sitting next to `X.png`
  /// (what `game_agent pack-assets` writes), so a freshly packed sheet shows up before
  /// anyone declares it. A manifest that can't be read is skipped, never fatal.
  factory AssetIndex.scan(String projectRoot) {
    final assets = Directory(p.join(projectRoot, 'assets'));
    final all = assets.existsSync()
        ? [
            for (final f in assets.listSync(recursive: true).whereType<File>())
              p.relative(f.path, from: projectRoot),
          ]
        : <String>[];
    all.sort();

    final atlases = <AtlasInfo>[];
    final inAtlas = <String>{};

    final catalog = AtlasCatalog.read(projectRoot);
    for (final entry in catalog.entries.entries) {
      final regions = _regionsOf(p.join(projectRoot, entry.value.manifest));
      if (regions == null) continue;
      atlases.add(
        AtlasInfo(
          id: entry.key,
          image: entry.value.image,
          manifest: entry.value.manifest,
          regions: regions,
          declared: true,
        ),
      );
      inAtlas
        ..add(entry.value.image)
        ..add(entry.value.manifest);
    }

    for (final path in all) {
      if (!path.endsWith('.json') || inAtlas.contains(path)) continue;
      final image = _siblingImage(projectRoot, path);
      if (image == null) continue;
      final regions = _regionsOf(p.join(projectRoot, path));
      if (regions == null) continue;
      atlases.add(
        AtlasInfo(
          id: p.basenameWithoutExtension(path),
          image: image,
          manifest: path,
          regions: regions,
          declared: false,
        ),
      );
      inAtlas
        ..add(path)
        ..add(image);
    }

    final prefabsDir = Directory(p.join(projectRoot, 'prefabs'));
    return AssetIndex(
      atlases: atlases..sort((a, b) => a.id.compareTo(b.id)),
      images: [
        for (final f in all)
          if (_imageExt.any(f.toLowerCase().endsWith) && !inAtlas.contains(f))
            f,
      ],
      audio: [
        for (final f in all)
          if (_audioExt.any(f.toLowerCase().endsWith)) f,
      ],
      data: [
        for (final f in all)
          if (f.endsWith('.json') &&
              !inAtlas.contains(f) &&
              !f.startsWith('assets/levels/') &&
              !f.startsWith('assets/studio_'))
            f,
      ],
      prefabs: prefabsDir.existsSync()
          ? ([
              for (final f in prefabsDir.listSync().whereType<File>())
                if (f.path.endsWith('.json'))
                  p.relative(f.path, from: projectRoot),
            ]..sort())
          : const [],
    );
  }

  /// The atlas with this id, or null.
  AtlasInfo? atlasById(String id) {
    for (final a in atlases) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// `atlasId -> sprite names` for the atlases the project **declares**, which is what
  /// a level can legitimately reference. Null when none are declared: with nothing to
  /// check against, a reference check would only produce noise.
  Map<String, Set<String>>? get declaredRegions {
    final declared = {
      for (final a in atlases)
        if (a.declared) a.id: a.regions.toSet(),
    };
    return declared.isEmpty ? null : declared;
  }

  static String? _siblingImage(String root, String manifestPath) {
    final stem = p.withoutExtension(manifestPath);
    for (final ext in ['.png', '.jpg', '.jpeg', '.webp']) {
      if (File(p.join(root, '$stem$ext')).existsSync()) return '$stem$ext';
    }
    return null;
  }

  static List<String>? _regionsOf(String manifestFile) {
    try {
      final json = jsonDecode(File(manifestFile).readAsStringSync());
      if (json is! Map || json['regions'] is! Map) return null;
      return [for (final k in (json['regions'] as Map).keys) '$k']..sort();
    } on Object {
      return null;
    }
  }
}
