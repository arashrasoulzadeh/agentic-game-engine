import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:engine_core/engine_core.dart';

import '../rendering/sprite_atlas.dart';

/// A cheap fingerprint of a file at a moment in time: change either field and
/// the file is considered changed. Modified-time alone misses a rewrite within
/// the filesystem's timestamp resolution; size alone misses an in-place edit.
class AssetStamp {
  final int modifiedMs;
  final int size;
  const AssetStamp(this.modifiedMs, this.size);

  @override
  bool operator ==(Object other) =>
      other is AssetStamp && other.modifiedMs == modifiedMs && other.size == size;

  @override
  int get hashCode => Object.hash(modifiedMs, size);
}

/// Where assets come from. The reloader only needs "what exists and how has it
/// changed" and "give me the bytes", so a directory on disk (`dart:io`, see
/// `directoryAssetSource`) and an in-memory fake for tests are interchangeable --
/// which also keeps this file compiling for web, where `dart:io` does not exist.
abstract class AssetSource {
  /// Every asset path (forward slashes, relative to the source root) with its
  /// current stamp.
  Future<Map<String, AssetStamp>> scan();

  Future<Uint8List> read(String path);
}

enum AssetChangeKind { added, changed, removed }

class AssetChange {
  final String path;
  final AssetChangeKind kind;
  const AssetChange(this.path, this.kind);

  @override
  String toString() => '${kind.name} $path';
}

/// Remembers the last scan and reports what differs from the next one.
class AssetChangeTracker {
  Map<String, AssetStamp> _known = {};

  /// Diffs [current] against the previous scan and remembers it. The first call
  /// reports everything as [AssetChangeKind.added]; call [prime] first to treat
  /// existing files as already loaded.
  List<AssetChange> diff(Map<String, AssetStamp> current) {
    final changes = <AssetChange>[
      for (final e in current.entries)
        if (!_known.containsKey(e.key))
          AssetChange(e.key, AssetChangeKind.added)
        else if (_known[e.key] != e.value)
          AssetChange(e.key, AssetChangeKind.changed),
      for (final path in _known.keys)
        if (!current.containsKey(path)) AssetChange(path, AssetChangeKind.removed),
    ]..sort((a, b) => a.path.compareTo(b.path));
    _known = Map.of(current);
    return changes;
  }

  /// Records [current] as the baseline without reporting anything.
  void prime(Map<String, AssetStamp> current) => _known = Map.of(current);
}

/// Reacts to one kind of asset changing.
abstract class AssetHandler {
  /// Whether this handler owns [path].
  bool handles(String path);

  /// Applies the change. A throw is caught by the reloader and reported to
  /// `onError`; the previous in-memory version must stay in place, so an
  /// asset saved half-written never takes the running game down.
  Future<void> reload(String path, AssetSource source);
}

/// Reloads a level JSON into a live `LevelHandle` when its file changes.
///
/// `LevelHandle.reload` validates before it tears anything down, so a level
/// saved with a typo throws and leaves the running level exactly as it was.
class LevelAssetHandler implements AssetHandler {
  LevelAssetHandler(this.path, this.handle);

  final String path;
  final LevelHandle handle;

  @override
  bool handles(String p) => p == path;

  @override
  Future<void> reload(String p, AssetSource source) async {
    final json = jsonDecode(utf8.decode(await source.read(p))) as Map<String, dynamic>;
    handle.reload(json);
  }
}

/// Reloads one sprite atlas (image + region manifest) into an `AtlasRegistry`.
///
/// Reloads when *either* file changes, so repacking only the manifest or only
/// the image both take effect. Registry lookups happen at draw time, so the new
/// atlas is used from the next frame; the old image is disposed afterwards.
class AtlasAssetHandler implements AssetHandler {
  AtlasAssetHandler({
    required this.registry,
    required this.atlasId,
    required this.imagePath,
    required this.manifestPath,
  });

  final AtlasRegistry registry;
  final String atlasId;
  final String imagePath;
  final String manifestPath;

  @override
  bool handles(String p) => p == imagePath || p == manifestPath;

  @override
  Future<void> reload(String p, AssetSource source) async {
    final manifest = jsonDecode(utf8.decode(await source.read(manifestPath))) as Map<String, dynamic>;
    final codec = await ui.instantiateImageCodec(await source.read(imagePath));
    final frame = await codec.getNextFrame();
    final fresh = SpriteAtlas.fromManifest(frame.image, manifest);
    final old = registry.tryResolve(atlasId);
    registry.register(atlasId, fresh);
    old?.image.dispose();
  }
}

/// Polls an [AssetSource] and dispatches changes to [handlers], so editing a
/// level, atlas or manifest while the game runs updates it without a restart.
///
/// Polling rather than `FileSystemEntity.watch`: native watchers differ across
/// macOS, Linux and Windows (and drop events on editors that save by
/// rename-and-replace), whereas a directory scan every few hundred ms is
/// identical everywhere and costs nothing for a project's asset count.
class AssetHotReloader {
  AssetHotReloader({
    required this.source,
    required this.handlers,
    this.interval = const Duration(milliseconds: 500),
    this.onReloaded,
    this.onError,
  });

  final AssetSource source;
  final List<AssetHandler> handlers;
  final Duration interval;

  /// Called after each handler succeeds.
  final void Function(AssetChange change)? onReloaded;

  /// Called when scanning or a handler fails; the game keeps running on the
  /// previous version of that asset.
  final void Function(AssetChange? change, Object error)? onError;

  final AssetChangeTracker _tracker = AssetChangeTracker();
  Timer? _timer;
  bool _polling = false;

  bool get isRunning => _timer != null;

  /// Baselines the current files (so nothing reloads on start), then polls
  /// every [interval].
  Future<void> start() async {
    if (_timer != null) return;
    _tracker.prime(await source.scan());
    _timer = Timer.periodic(interval, (_) => poll());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// One scan-diff-dispatch cycle. Public so a game can force a refresh and so
  /// tests don't depend on timers. Overlapping calls are ignored: a slow reload
  /// must not stack up behind the next tick.
  Future<List<AssetChange>> poll() async {
    if (_polling) return const [];
    _polling = true;
    try {
      final Map<String, AssetStamp> now;
      try {
        now = await source.scan();
      } catch (e) {
        onError?.call(null, e);
        return const [];
      }
      final changes = _tracker.diff(now);
      for (final change in changes) {
        if (change.kind == AssetChangeKind.removed) continue;
        for (final handler in handlers.where((h) => h.handles(change.path))) {
          try {
            await handler.reload(change.path, source);
            onReloaded?.call(change);
          } catch (e) {
            onError?.call(change, e);
          }
        }
      }
      return changes;
    } finally {
      _polling = false;
    }
  }
}
