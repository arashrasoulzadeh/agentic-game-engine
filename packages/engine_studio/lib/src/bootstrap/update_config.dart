import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:path/path.dart' as p;

import 'bootstrapper.dart';

/// Where the studio checks for updates, from the `updates` object in `studio_prefs.json`:
///
/// ```json
/// { "updates": { "manifestUrl": "https://example.com/studio/manifest.json",
///                "publicKey": "<base64 of the publisher's 32-byte Ed25519 key>" } }
/// ```
///
/// Both are required: without a key nothing could be verified, so an unconfigured studio makes
/// no network requests at all.
class UpdateConfig {
  UpdateConfig(this.manifestUrl, this.publicKey);

  final String manifestUrl;
  final List<int> publicKey;

  /// The config in [prefs], or null when it is absent or incomplete.
  static UpdateConfig? load(File prefs) {
    try {
      final json = jsonDecode(prefs.readAsStringSync());
      final updates = json is Map ? json['updates'] : null;
      if (updates is! Map) return null;
      final url = updates['manifestUrl'];
      final key = updates['publicKey'];
      if (url is! String || url.isEmpty || key is! String) return null;
      final bytes = base64Decode(key);
      return bytes.length == 32 ? UpdateConfig(url, bytes) : null;
    } on Object {
      return null;
    }
  }

  /// A [Bootstrapper] for this config, caching under [cacheDir].
  Bootstrapper bootstrapper(Directory cacheDir, {ReleaseServer? server}) =>
      Bootstrapper(
        server: server ?? HttpReleaseServer(manifestUrl),
        verifier: ReleaseManifestVerifier.fromPublicKeyBytes(publicKey),
        cacheDir: cacheDir,
      );
}

/// The downloaded-packs folder, beside the studio prefs.
Directory studioCacheDir({Map<String, String>? env}) {
  final e = env ?? Platform.environment;
  final home = e['HOME'] ?? e['USERPROFILE'] ?? '.';
  return Directory(p.join(home, '.game_agent', 'cache'));
}
