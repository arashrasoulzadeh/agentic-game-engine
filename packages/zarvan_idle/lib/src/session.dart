import 'dart:async';

import 'package:zarvan_core/zarvan_core.dart';

import 'package:zarvan_core/zarvan_core_idle.dart';
import 'ui/idle_controller.dart';

export 'cloud_save_store.dart';
export 'return_notifier.dart';
export 'save_store.dart';

import 'cloud_save_store.dart';
import 'return_notifier.dart';
import 'save_store.dart';

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
    this.notifier,
    this.whileAway,
    this.awaySlices = 200,
    this.returnMessage =
        'Your generators are full - come collect your earnings.',
  }) : migrator = migrator ?? SaveMigrator(currentVersion: 1),
       _clock = clock ?? DateTime.now;

  final IdleController controller;
  final SaveStore store;
  final SaveMigrator migrator;
  final OfflineConfig offline;
  final DateTime Function() _clock;

  /// For economies whose rates change while the player is away (auto-buyers): called between
  /// [awaySlices] equal parts of the catch-up, so it can buy things and call `recomputeIncome` before the
  /// next part earns at the new rate. Null (the default) pays the whole absence at the current rates.
  final void Function()? whileAway;

  /// How many parts the catch-up is split into when [whileAway] is set.
  final int awaySlices;

  /// Reminds the player when the offline cap is reached; null for no reminders.
  final ReturnNotifier? notifier;

  /// Text of that reminder.
  final String returnMessage;

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
    final step = whileAway;
    final summary = step == null
        ? OfflineProgress.catchUp(
            controller.wallet,
            lastActiveAt: from,
            now: _clock(),
            config: offline,
          )
        : OfflineProgress.applyInSlices(
            controller.wallet,
            OfflineProgress.creditFor(
              lastActiveAt: from,
              now: _clock(),
              config: offline,
            ),
            slices: awaySlices,
            between: step,
            config: offline,
          );
    if (summary.isEmpty) return null;
    controller.analytics?.offlineReturn(summary);
    final stats = controller.world.componentsOf<IdleStats>();
    if (stats.length > 0) {
      stats.denseAt(0).credit(summary.gained);
    }
    checkAchievements(controller.world, controller.wallet);
    controller.refresh();
    return summary;
  }

  /// Pays [summary]'s earnings a second time (the "watch an ad for 2x" reward), counted in the stats like
  /// the first payment. Call it only after the player earned the bonus.
  void doubleOffline(OfflineSummary summary) {
    for (final e in summary.gained.entries) {
      controller.wallet.add(e.key, e.value);
    }
    final stats = controller.world.componentsOf<IdleStats>();
    if (stats.length > 0) stats.denseAt(0).credit(summary.gained);
    checkAchievements(controller.world, controller.wallet);
    controller.refresh();
  }

  /// The app went to the background: save and stop the clock (there is nothing to show while away).
  void onPause() {
    save();
    notifier?.schedule(
      OfflineProgress.untilCap(
        leftAt: _lastActiveAt!,
        now: _lastActiveAt!,
        config: offline,
      ),
      returnMessage,
    );
    controller.stop();
  }

  /// The app came back: pay out the time spent away (capped, at the configured efficiency), then resume
  /// stepping. Returns what was earned, or null if it was too short to count.
  OfflineSummary? onResume() {
    notifier?.cancel();
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

  /// Reconciles the local game with [cloud]: whichever was saved later wins, unless [resolve] is given -
  /// it is shown both saves (the whole save maps) when they differ and returns true to take the cloud one
  /// (so a game can ask the player). An empty side is filled from the other. A pulled save replaces the
  /// local game without paying offline time (the player was playing elsewhere).
  Future<CloudSyncResult> syncCloud(
    CloudSaveStore cloud, {
    bool Function(Map<String, dynamic> local, Map<String, dynamic> remote)?
    resolve,
  }) async {
    final remote = await cloud.fetch();
    // The previous save's time is when this device was last known active; saving now would make the
    // local side look newer than anything the cloud could hold.
    final previousAt = DateTime.tryParse(
      store.read()?['lastActiveAt'] as String? ?? '',
    );
    save();
    final local = store.read()!;
    if (remote == null) {
      await cloud.push(local);
      return CloudSyncResult.pushed;
    }
    final migrated = migrator.migrate(remote);
    final remoteAt = DateTime.tryParse(
      migrated['lastActiveAt'] as String? ?? '',
    );
    final localAt = previousAt;
    final hasLocalProgress = _hasProgress();
    final bool takeRemote;
    if (!hasLocalProgress) {
      takeRemote = true;
    } else if (resolve != null && remoteAt != localAt) {
      takeRemote = resolve(local, migrated);
    } else {
      takeRemote =
          remoteAt != null && (localAt == null || remoteAt.isAfter(localAt));
    }
    if (takeRemote) {
      final world = migrated['world'];
      if (world is! Map) {
        throw const SaveFormatException('The cloud save has no game data.');
      }
      WorldSnapshot.fromJson(
        world.cast<String, dynamic>(),
      ).restoreInto(controller.world);
      store.write(migrated);
      _lastActiveAt = _clock();
      controller.refresh();
      return CloudSyncResult.pulled;
    }
    if (remoteAt == localAt) return CloudSyncResult.unchanged;
    await cloud.push(local);
    return CloudSyncResult.pushed;
  }

  bool _hasProgress() {
    final stats = controller.world.componentsOf<IdleStats>();
    if (stats.length == 0) return true;
    final s = stats.denseAt(0);
    return s.lifetimeEarned.isNotEmpty || s.taps > 0 || s.secondsPlayed > 0;
  }

  void dispose() => stopAutosave();
}
