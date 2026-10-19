import 'dart:io';
import 'dart:typed_data';

import 'asset_hot_reload.dart';

/// Scans [path] recursively; asset paths are relative to it, with forward
/// slashes on every platform. Returns an empty scan if the directory does not
/// exist (yet), so starting before the first asset is saved is fine.
AssetSource? directoryAssetSource(String path) =>
    _DirectoryAssetSource(Directory(path));

class _DirectoryAssetSource implements AssetSource {
  _DirectoryAssetSource(this.root);

  final Directory root;

  String _relative(String full) {
    final base = root.absolute.path;
    var rel = full.startsWith(base) ? full.substring(base.length) : full;
    rel = rel.replaceAll(r'\', '/');
    return rel.startsWith('/') ? rel.substring(1) : rel;
  }

  @override
  Future<Map<String, AssetStamp>> scan() async {
    if (!await root.exists()) return {};
    final stamps = <String, AssetStamp>{};
    await for (final e in root.absolute.list(
      recursive: true,
      followLinks: false,
    )) {
      if (e is! File) continue;
      final stat = await e.stat();
      stamps[_relative(e.path)] = AssetStamp(
        stat.modified.millisecondsSinceEpoch,
        stat.size,
      );
    }
    return stamps;
  }

  @override
  Future<Uint8List> read(String path) =>
      File('${root.absolute.path}/$path').readAsBytes();
}
