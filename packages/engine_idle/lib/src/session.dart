import 'dart:async';

import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_io.dart' show AtomicSave;

import 'progression.dart';
import 'ui/idle_controller.dart';

/// Where a game keeps its save. An interface so tests (and web, where there is no file system) can
/// supply their own.
abstract class SaveStore {
  /// The newest readable save, or null.
  Map<String, dynamic>? read();

  /// Stores [save], replacing the previous one.
  void write(Map<String, dynamic> save);
}

/// A [SaveStore] in memory, for tests.
class MemorySaveStore implements SaveStore {
  Map<String, dynamic>? value;

  @override
  Map<String, dynamic>? read() => value;

  @override
  void write(Map<String, dynamic> save) => value = save;
}

/// A [SaveStore] on disk using `AtomicSave`: a crash mid-write leaves the previous save, and a corrupt
/// file falls back to the backup.
class FileSaveStore implements SaveStore {
  FileSaveStore(String path) : _file = AtomicSave(path);
  final AtomicSave _file;

  @override
  Map<String, dynamic>? read() => _file.read();

  @override
  void write(Map<String, dynamic> save) => _file.write(save);
}

/// Saving, loading and offline catch-up for an idle game, wired to the app's lifecycle.
///
/// A save is the whole world (`WorldSnapshot`) plus `lastActiveAt` and a `saveVersion`, so everything the
/// economy, stats, prestige and achievements hold is restored exactly. Time enters only through [clock],
/// which tests replace.
class IdleSession {
  IdleSession({
    required this.controller,
    required this.store,
    SaveMigrator? migrator,
    this.offline = const OfflineConfig(),
    DateTime Function()? clock,
  }) : migrator = migrator ?? SaveMigrator(currentVersion: 1),
       _clock = clock ?? DateTime.now;

  final IdleController controller;
  final SaveStore store;
  final SaveMigrator migrator;
  final OfflineConfig offline;
  final DateTime Function() _clock;

  DateTime? _lastActiveAt;
  Timer? _autosave;

  /// When the game was last known to be running (set by [save] and [onPause]).
  DateTime? get lastActiveAt => _lastActiveAt;

  /// Writes the current state. Call it after important actions and from [onPause]; [startAutosave] does
  /// it periodically.
  void save() {
    _lastActiveAt = _clock();
    store.write(
      migrator.stamp({
        'world': WorldSnapshot.capture(controller.world).toJson(),
        'lastActiveAt': _lastActiveAt!.toUtc().toIso8601String(),
      }),
    );
  }

  /// Restores the saved game (migrating an old save first) and pays out the time since it was written.
  ///
  /// Returns the catch-up summary, or null if there was no save (a new game) or nothing was earned. A
  /// save from a newer game, or a damaged one, throws [SaveFormatException] - show its message; the file
  /// is left untouched.
  OfflineSummary? load() {
    final raw = store.read();
    if (raw == null) return null;
    final data = migrator.migrate(raw);
    final world = data['world'];
    if (world is! Map) {
      throw const SaveFormatException('The save has no game data.');
    }
    WorldSnapshot.fromJson(
      world.cast<String, dynamic>(),
    ).restoreInto(controller.world);

    final left = DateTime.tryParse(data['lastActiveAt'] as String? ?? '');
    _lastActiveAt = left;
    if (left == null) return null;
    return _catchUp(left);
  }

  OfflineSummary? _catchUp(DateTime from) {
    final summary = OfflineProgress.catchUp(
      controller.wallet,
      lastActiveAt: from,
      now: _clock(),
      config: offline,
    );
    if (summary.isEmpty) return null;
    final stats = controller.world.storeOf<IdleStats>();
    if (stats.length > 0) {
      stats.denseAt(0).credit(summary.gained);
    }
    checkAchievements(controller.world, controller.wallet);
    controller.refresh();
    return summary;
  }

  /// The app went to the background: save and stop the clock (there is nothing to show while away).
  void onPause() {
    save();
    controller.stop();
  }

  /// The app came back: pay out the time spent away (capped, at the configured efficiency), then resume
  /// stepping. Returns what was earned, or null if it was too short to count.
  OfflineSummary? onResume() {
    final from = _lastActiveAt;
    final summary = from == null ? null : _catchUp(from);
    _lastActiveAt = _clock();
    controller.start();
    return summary;
  }

  /// Saves every [interval] while the game runs.
  void startAutosave([Duration interval = const Duration(seconds: 30)]) {
    _autosave?.cancel();
    _autosave = Timer.periodic(interval, (_) => save());
  }

  /// Stops autosaving.
  void stopAutosave() {
    _autosave?.cancel();
    _autosave = null;
  }

  /// A copyable text of the current state, for moving to another device.
  String exportCode() => SaveCodec.export(
    migrator.stamp({
      'world': WorldSnapshot.capture(controller.world).toJson(),
      'lastActiveAt': _clock().toUtc().toIso8601String(),
    }),
  );

  /// Replaces the game with the one in [code] (see [exportCode]). Throws [SaveFormatException] with a
  /// player-readable reason if it is damaged, foreign or from a newer game; the current game is untouched
  /// in that case. Does not pay offline time (the code was made just now by definition of "move").
  void importCode(String code) {
    final data = migrator.migrate(SaveCodec.import(code));
    final world = data['world'];
    if (world is! Map) {
      throw const SaveFormatException('The save has no game data.');
    }
    WorldSnapshot.fromJson(
      world.cast<String, dynamic>(),
    ).restoreInto(controller.world);
    _lastActiveAt = _clock();
    controller.refresh();
  }

  void dispose() => stopAutosave();
}
