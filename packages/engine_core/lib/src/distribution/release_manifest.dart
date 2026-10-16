import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// One downloadable item in a [ReleaseManifest]: a project template, sample
/// level, node/brush pack, or engine version the bootstrap window can fetch
/// (STUDIO_TODO.md 2.13/3.19).
class ManifestItem {
  final String name;
  final String url;
  final int size;

  /// Lowercase hex SHA-256 of the downloaded bytes. The bootstrap window
  /// refuses anything that doesn't match, rather than trusting [size] alone.
  final String sha256;

  const ManifestItem({
    required this.name,
    required this.url,
    required this.size,
    required this.sha256,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'size': size,
    'sha256': sha256,
  };

  factory ManifestItem.fromJson(Map<String, dynamic> json) => ManifestItem(
    name: json['name'] as String,
    url: json['url'] as String,
    size: json['size'] as int,
    sha256: json['sha256'] as String,
  );
}

/// A release manifest: the studio version it describes and every item the
/// bootstrap window may need to download. Plain data — parsing this never
/// executes anything; see [ReleaseManifestVerifier] for what makes a
/// manifest trustworthy enough to act on.
class ReleaseManifest {
  final String studioVersion;
  final List<ManifestItem> items;

  const ReleaseManifest({required this.studioVersion, required this.items});

  Map<String, dynamic> toJson() => {
    'studioVersion': studioVersion,
    'items': [for (final item in items) item.toJson()],
  };

  factory ReleaseManifest.fromJson(Map<String, dynamic> json) =>
      ReleaseManifest(
        studioVersion: json['studioVersion'] as String,
        items: [
          for (final item in (json['items'] as List))
            ManifestItem.fromJson((item as Map).cast<String, dynamic>()),
        ],
      );

  /// The exact bytes a signature is computed over: canonical JSON (fixed key
  /// order, as [toJson] always emits it), UTF-8 encoded. Signing or
  /// verifying anything other than this exact encoding of this exact map
  /// will not match.
  Uint8List get signedBytes => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));
}

/// Why a manifest or one of its items was rejected, so the bootstrap window
/// can say something more useful than "invalid."
enum ManifestRejection { unsigned, invalidSignature, checksumMismatch }

/// The result of checking a manifest: either it's trustworthy
/// ([ReleaseManifestCheck.ok]), or it names why it isn't.
class ReleaseManifestCheck {
  final bool ok;
  final ManifestRejection? rejection;

  const ReleaseManifestCheck._(this.ok, this.rejection);

  static const valid = ReleaseManifestCheck._(true, null);

  factory ReleaseManifestCheck.rejected(ManifestRejection reason) =>
      ReleaseManifestCheck._(false, reason);
}

/// Verifies a [ReleaseManifest]'s Ed25519 signature against a known public
/// key, and verifies a downloaded item's bytes against its declared
/// checksum. The studio ships with the public key baked in; only the
/// release pipeline holds the matching private key, so a manifest served
/// from a compromised or spoofed CDN can't pass this check without it.
class ReleaseManifestVerifier {
  final SimplePublicKey publicKey;
  static final Ed25519 _algorithm = Ed25519();

  const ReleaseManifestVerifier(this.publicKey);

  /// Checks [manifest]'s [signature] (raw bytes, not base64/hex) against
  /// [publicKey]. A null or empty signature is reported as [unsigned],
  /// distinct from a present-but-wrong one ([invalidSignature]), since the
  /// bootstrap window should say "this manifest isn't signed at all"
  /// differently from "this manifest's signature doesn't check out."
  ///
  /// [signature] is untrusted input straight from wherever the manifest
  /// came from, so a malformed one (wrong length, garbage bytes) must come
  /// back as [invalidSignature] like any other forged signature, not throw
  /// — `Ed25519.verify` throws a bare `StateError` on a wrong-length
  /// signature rather than returning false, which would otherwise crash
  /// the bootstrap window instead of just rejecting the manifest.
  Future<ReleaseManifestCheck> verify(
    ReleaseManifest manifest,
    List<int>? signature,
  ) async {
    if (signature == null || signature.isEmpty) {
      return ReleaseManifestCheck.rejected(ManifestRejection.unsigned);
    }
    bool valid;
    try {
      valid = await _algorithm.verify(
        manifest.signedBytes,
        signature: Signature(signature, publicKey: publicKey),
      );
    } on Object {
      valid = false;
    }
    if (!valid) {
      return ReleaseManifestCheck.rejected(ManifestRejection.invalidSignature);
    }
    return ReleaseManifestCheck.valid;
  }

  /// Checks downloaded [bytes] against [item]'s declared SHA-256. The
  /// bootstrap window calls this after every download, before the file is
  /// kept or used for anything.
  static ReleaseManifestCheck verifyChecksum(ManifestItem item, List<int> bytes) {
    final digest = sha256.convert(bytes).toString();
    if (digest != item.sha256) {
      return ReleaseManifestCheck.rejected(ManifestRejection.checksumMismatch);
    }
    return ReleaseManifestCheck.valid;
  }
}

/// Signs a manifest with a private key — the release pipeline's job, not
/// the studio's. Kept here (rather than only in a separate tool) so the
/// exact bytes a signature covers ([ReleaseManifest.signedBytes]) can never
/// drift between what signs a release and what [ReleaseManifestVerifier]
/// checks — and so tests can generate a real, valid signature without
/// depending on a fixture file.
class ReleaseManifestSigner {
  static final Ed25519 _algorithm = Ed25519();

  /// A fresh Ed25519 keypair, for generating a release's signing key or for
  /// a test that needs a real key pair rather than a canned one.
  static Future<SimpleKeyPair> generateKeyPair() =>
      _algorithm.newKeyPair();

  /// Signs [manifest] with [privateKey], returning the raw signature bytes
  /// to publish alongside the manifest (e.g. as `manifest.json.sig`).
  static Future<List<int>> sign(
    ReleaseManifest manifest,
    SimpleKeyPair privateKey,
  ) async {
    final signature = await _algorithm.sign(
      manifest.signedBytes,
      keyPair: privateKey,
    );
    return signature.bytes;
  }
}
