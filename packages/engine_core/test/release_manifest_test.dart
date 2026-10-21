import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

ReleaseManifest _manifest() => const ReleaseManifest(
  studioVersion: '1.2.0',
  items: [
    ManifestItem(
      name: 'default_game template',
      url: 'https://example.com/templates/default_game.zip',
      size: 4096,
      sha256: 'deadbeef',
    ),
  ],
);

void main() {
  keyBytesTests();
  group('ReleaseManifest JSON round-trip', () {
    test('toJson/fromJson preserves every field', () {
      final manifest = _manifest();
      final decoded = ReleaseManifest.fromJson(manifest.toJson());
      expect(decoded.studioVersion, manifest.studioVersion);
      expect(decoded.items.single.name, manifest.items.single.name);
      expect(decoded.items.single.url, manifest.items.single.url);
      expect(decoded.items.single.size, manifest.items.single.size);
      expect(decoded.items.single.sha256, manifest.items.single.sha256);
    });

    test('signedBytes is stable for the same manifest', () {
      final manifest = _manifest();
      expect(manifest.signedBytes, _manifest().signedBytes);
    });
  });

  group('ReleaseManifestVerifier signature checks', () {
    late SimpleKeyPair keyPair;
    late SimplePublicKey publicKey;
    late ReleaseManifestVerifier verifier;
    late ReleaseManifest manifest;

    setUp(() async {
      keyPair = await ReleaseManifestSigner.generateKeyPair();
      publicKey = await keyPair.extractPublicKey();
      verifier = ReleaseManifestVerifier(publicKey);
      manifest = _manifest();
    });

    test('a correctly signed manifest is valid', () async {
      final signature = await ReleaseManifestSigner.sign(manifest, keyPair);
      final result = await verifier.verify(manifest, signature);
      expect(result.ok, isTrue);
      expect(result.rejection, isNull);
    });

    test('a null signature is rejected as unsigned, not invalid', () async {
      final result = await verifier.verify(manifest, null);
      expect(result.ok, isFalse);
      expect(result.rejection, ManifestRejection.unsigned);
    });

    test('an empty signature is rejected as unsigned', () async {
      final result = await verifier.verify(manifest, const []);
      expect(result.ok, isFalse);
      expect(result.rejection, ManifestRejection.unsigned);
    });

    test(
      'a manifest tampered with after signing fails signature verification',
      () async {
        final signature = await ReleaseManifestSigner.sign(manifest, keyPair);
        final tampered = ReleaseManifest(
          studioVersion: manifest.studioVersion,
          items: [
            ManifestItem(
              name: manifest.items.single.name,
              url: manifest.items.single.url,
              size: 999999, // changed after signing
              sha256: manifest.items.single.sha256,
            ),
          ],
        );
        final result = await verifier.verify(tampered, signature);
        expect(result.ok, isFalse);
        expect(result.rejection, ManifestRejection.invalidSignature);
      },
    );

    test('a signature from a different key pair is rejected', () async {
      final otherKeyPair = await ReleaseManifestSigner.generateKeyPair();
      final signature = await ReleaseManifestSigner.sign(
        manifest,
        otherKeyPair,
      );
      final result = await verifier.verify(manifest, signature);
      expect(result.ok, isFalse);
      expect(result.rejection, ManifestRejection.invalidSignature);
    });

    test('garbage bytes in place of a real signature are rejected', () async {
      final result = await verifier.verify(
        manifest,
        utf8.encode('not a real signature'),
      );
      expect(result.ok, isFalse);
      expect(result.rejection, ManifestRejection.invalidSignature);
    });
  });

  group('ReleaseManifestVerifier.verifyChecksum', () {
    test('matching bytes pass', () {
      final bytes = utf8.encode('the actual file contents');
      final item = ManifestItem(
        name: 'thing',
        url: 'https://example.com/thing',
        size: bytes.length,
        sha256: crypto.sha256.convert(bytes).toString(),
      );
      final result = ReleaseManifestVerifier.verifyChecksum(item, bytes);
      expect(result.ok, isTrue);
    });

    test('a checksum mismatch is reported, not silently accepted', () {
      final item = ManifestItem(
        name: 'thing',
        url: 'https://example.com/thing',
        size: 10,
        sha256: crypto.sha256
            .convert(utf8.encode("the original contents"))
            .toString(),
      );
      final corrupted = utf8.encode('different bytes entirely');
      final result = ReleaseManifestVerifier.verifyChecksum(item, corrupted);
      expect(result.ok, isFalse);
      expect(result.rejection, ManifestRejection.checksumMismatch);
    });
  });
}

void keyBytesTests() {
  test(
    'a verifier built from raw public-key bytes accepts the matching signature only',
    () async {
      final pair = await ReleaseManifestSigner.generateKeyPair();
      final bytes = (await pair.extractPublicKey()).bytes;
      final manifest = _manifest();
      final sig = await ReleaseManifestSigner.sign(manifest, pair);

      final verifier = ReleaseManifestVerifier.fromPublicKeyBytes(bytes);
      expect((await verifier.verify(manifest, sig)).ok, isTrue);

      final other = await ReleaseManifestSigner.generateKeyPair();
      final wrong = ReleaseManifestVerifier.fromPublicKeyBytes(
        (await other.extractPublicKey()).bytes,
      );
      expect(
        (await wrong.verify(manifest, sig)).rejection,
        ManifestRejection.invalidSignature,
      );
    },
  );
}
