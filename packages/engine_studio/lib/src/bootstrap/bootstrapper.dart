import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:path/path.dart' as p;

/// Where the studio gets its signed release manifest and the files it lists. An interface so
/// the logic here is tested against a fake server (including one that is unreachable); the app
/// uses [HttpReleaseServer].
abstract class ReleaseServer {
  /// The manifest and its Ed25519 signature. Throws when the server cannot be reached.
  Future<({ReleaseManifest manifest, List<int>? signature})> fetchManifest();

  /// The bytes at [url], reporting progress. Throws on failure.
  Future<List<int>> download(
    String url, {
    void Function(int received, int total)? onProgress,
  });
}

/// A [ReleaseServer] over plain HTTP(S): `GET <manifestUrl>` returns the manifest JSON, and the
/// signature (base64) is at `<manifestUrl>.sig`.
class HttpReleaseServer implements ReleaseServer {
  HttpReleaseServer(this.manifestUrl, {HttpClient? client})
    : _client = client ?? HttpClient();

  final String manifestUrl;
  final HttpClient _client;

  @override
  Future<({ReleaseManifest manifest, List<int>? signature})>
  fetchManifest() async {
    final body = utf8.decode(await download(manifestUrl));
    final manifest = ReleaseManifest.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
    List<int>? signature;
    try {
      signature = base64Decode(
        utf8.decode(await download('$manifestUrl.sig')).trim(),
      );
    } on Object {
      signature = null; // reported as "unsigned" by the verifier
    }
    return (manifest: manifest, signature: signature);
  }

  @override
  Future<List<int>> download(
    String url, {
    void Function(int received, int total)? onProgress,
  }) async {
    final request = await _client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      onProgress?.call(bytes.length, response.contentLength);
    }
    return bytes;
  }
}

/// What the user chose for an item. Nothing installs without [accept].
enum Decision { pending, accept, defer, skip }

/// How an item in the manifest relates to what is already installed.
enum ItemState { missing, updateAvailable, current }

/// Where an item's install stands.
enum InstallStatus { notStarted, downloading, installed, failed }

/// One line of the bootstrap window: a manifest item, how it differs from what is installed,
/// the user's decision, and the result of installing it.
class BootstrapItem {
  BootstrapItem(this.item, this.state, {this.decision = Decision.pending});

  final ManifestItem item;
  final ItemState state;
  Decision decision;
  InstallStatus status = InstallStatus.notStarted;
  int received = 0;

  /// Why the last install failed (a download error or `checksum mismatch`), for the window.
  String? error;

  double get progress =>
      item.size <= 0 ? 0 : (received / item.size).clamp(0.0, 1.0);
}

/// Why no plan could be made from the server.
enum PlanProblem { none, offline, rejected }

/// The result of checking the server: the items to show, and whether this is an offline view
/// of what was installed last time or a manifest that failed verification.
class BootstrapPlan {
  BootstrapPlan(
    this.items, {
    this.problem = PlanProblem.none,
    this.rejection,
    this.detail,
  });

  final List<BootstrapItem> items;
  final PlanProblem problem;
  final ManifestRejection? rejection;
  final String? detail;

  /// Items that need a decision: not installed, or a newer version exists.
  Iterable<BootstrapItem> get actionable =>
      items.where((i) => i.state != ItemState.current);
}

/// Keeps downloaded packs in [cacheDir] and decides what needs downloading.
///
/// Rules (design §2.13): the manifest must verify before anything is offered; each file's
/// SHA-256 must match before it replaces the installed copy, and the replacement is atomic, so
/// a failed or corrupt download leaves the previous version in place; nothing installs without
/// an explicit [Decision.accept]; if the server cannot be reached the studio still opens, with
/// what is cached.
class Bootstrapper {
  Bootstrapper({
    required this.server,
    required this.verifier,
    required this.cacheDir,
  });

  final ReleaseServer server;
  final ReleaseManifestVerifier verifier;
  final Directory cacheDir;

  File get _stateFile => File(p.join(cacheDir.path, 'installed.json'));

  /// name -> sha256 of the installed copy.
  Map<String, String> get installed => _readState().$1;

  /// name -> sha256 the user chose to skip (not offered again until it changes).
  Map<String, String> get skipped => _readState().$2;

  /// Where the installed copy of [name] lives, or null if not installed.
  File? fileFor(String name) {
    if (!installed.containsKey(name)) return null;
    final f = File(p.join(cacheDir.path, 'packs', _safe(name)));
    return f.existsSync() ? f : null;
  }

  /// Fetches and verifies the manifest and works out what to offer.
  Future<BootstrapPlan> check() async {
    final ({ReleaseManifest manifest, List<int>? signature}) fetched;
    try {
      fetched = await server.fetchManifest();
    } on Object catch (e) {
      return BootstrapPlan(
        const [],
        problem: PlanProblem.offline,
        detail: '$e',
      );
    }
    final verdict = await verifier.verify(fetched.manifest, fetched.signature);
    if (!verdict.ok) {
      return BootstrapPlan(
        const [],
        problem: PlanProblem.rejected,
        rejection: verdict.rejection,
      );
    }
    final have = installed;
    final skip = skipped;
    final items = <BootstrapItem>[];
    for (final item in fetched.manifest.items) {
      final current = have[item.name];
      final state = current == null
          ? ItemState.missing
          : current == item.sha256
          ? ItemState.current
          : ItemState.updateAvailable;
      final bi = BootstrapItem(item, state);
      if (skip[item.name] == item.sha256) bi.decision = Decision.skip;
      items.add(bi);
    }
    return BootstrapPlan(items);
  }

  /// Records that the user skipped this exact version.
  void skip(BootstrapItem bi) {
    bi.decision = Decision.skip;
    final (inst, skp) = _readState();
    skp[bi.item.name] = bi.item.sha256;
    _writeState(inst, skp);
  }

  /// Downloads, verifies and installs every accepted item that is not already installed,
  /// updating each item's status and progress; [onChanged] fires after each change. A failure
  /// on one item does not stop the others. Returns the items that failed (retry by calling
  /// again - they stay accepted).
  Future<List<BootstrapItem>> installAccepted(
    List<BootstrapItem> items, {
    void Function()? onChanged,
  }) async {
    final failed = <BootstrapItem>[];
    for (final bi in items) {
      final wanted =
          bi.decision == Decision.accept &&
          bi.status != InstallStatus.installed &&
          bi.state != ItemState.current;
      if (!wanted) continue;
      bi.status = InstallStatus.downloading;
      bi.received = 0;
      bi.error = null;
      onChanged?.call();
      try {
        final bytes = await server.download(
          bi.item.url,
          onProgress: (received, total) {
            bi.received = received;
            onChanged?.call();
          },
        );
        final check = ReleaseManifestVerifier.verifyChecksum(bi.item, bytes);
        if (!check.ok) {
          throw const FormatException(
            'checksum mismatch: the download does not match the signed manifest',
          );
        }
        _store(bi.item, bytes);
        bi.status = InstallStatus.installed;
        bi.received = bi.item.size;
      } on Object catch (e) {
        bi.status = InstallStatus.failed;
        bi.error = e is FormatException ? e.message : '$e';
        failed.add(bi);
      }
      onChanged?.call();
    }
    return failed;
  }

  void _store(ManifestItem item, List<int> bytes) {
    final dir = Directory(p.join(cacheDir.path, 'packs'))
      ..createSync(recursive: true);
    final target = File(p.join(dir.path, _safe(item.name)));
    final temp = File('${target.path}.part')..writeAsBytesSync(bytes);
    temp.renameSync(
      target.path,
    ); // atomic: the old copy is replaced only by a complete, verified one
    final (inst, skp) = _readState();
    inst[item.name] = item.sha256;
    skp.remove(item.name);
    _writeState(inst, skp);
  }

  (Map<String, String>, Map<String, String>) _readState() {
    try {
      final json =
          jsonDecode(_stateFile.readAsStringSync()) as Map<String, dynamic>;
      Map<String, String> read(String k) => {
        for (final e in ((json[k] as Map?) ?? const {}).entries)
          e.key as String: e.value as String,
      };
      return (read('installed'), read('skipped'));
    } on Object {
      return ({}, {});
    }
  }

  void _writeState(Map<String, String> installed, Map<String, String> skipped) {
    cacheDir.createSync(recursive: true);
    _stateFile.writeAsStringSync(
      jsonEncode({'installed': installed, 'skipped': skipped}),
    );
  }

  /// A file name for a manifest item name (which can contain spaces and slashes).
  static String _safe(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}
