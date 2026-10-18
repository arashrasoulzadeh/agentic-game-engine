import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:engine_core/engine_core.dart';
import 'package:engine_studio/src/bootstrap/bootstrapper.dart';
import 'package:flutter_test/flutter_test.dart';

String sha(List<int> bytes) => crypto.sha256.convert(bytes).toString();

/// A server we control: files by url, a manifest that is signed (or not), and switches for
/// "unreachable" and "this download is corrupt".
class FakeReleaseServer implements ReleaseServer {
  FakeReleaseServer(this.signer);

  final Future<List<int>> Function(ReleaseManifest) signer;
  final Map<String, List<int>> files = {};
  List<ManifestItem> items = [];
  bool unreachable = false;
  bool unsigned = false;
  Set<String> failDownloads = {};
  List<String> downloads = [];

  void put(String name, String content) {
    final bytes = utf8.encode(content);
    files['https://x/$name'] = bytes;
    items = [
      ...items.where((i) => i.name != name),
      ManifestItem(
        name: name,
        url: 'https://x/$name',
        size: bytes.length,
        sha256: sha(bytes),
      ),
    ];
  }

  @override
  Future<({ReleaseManifest manifest, List<int>? signature})>
  fetchManifest() async {
    if (unreachable) throw const SocketException('no route to host');
    final manifest = ReleaseManifest(
      studioVersion: '1.0.0',
      items: List.of(items),
    );
    return (
      manifest: manifest,
      signature: unsigned ? null : await signer(manifest),
    );
  }

  @override
  Future<List<int>> download(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    downloads.add(url);
    if (unreachable || failDownloads.contains(url)) {
      throw const SocketException('connection reset');
    }
    final bytes = files[url]!;
    onProgress?.call(bytes.length ~/ 2, bytes.length);
    onProgress?.call(bytes.length, bytes.length);
    return bytes;
  }
}

Future<
  ({
    Bootstrapper boot,
    FakeReleaseServer server,
    Directory dir,
    Directory Function() reopen,
  })
>
bootstrapRig() async {
  final pair = await ReleaseManifestSigner.generateKeyPair();
  final pub = await pair.extractPublicKey();
  final server = FakeReleaseServer((m) => ReleaseManifestSigner.sign(m, pair));
  final dir = Directory.systemTemp.createTempSync('bootstrap');
  addTearDown(() => dir.deleteSync(recursive: true));
  final boot = Bootstrapper(
    server: server,
    verifier: ReleaseManifestVerifier(pub),
    cacheDir: dir,
  );
  return (boot: boot, server: server, dir: dir, reopen: () => dir);
}
