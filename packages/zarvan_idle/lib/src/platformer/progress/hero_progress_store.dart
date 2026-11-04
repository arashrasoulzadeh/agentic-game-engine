import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../save_store.dart';
import 'hero_progress.dart';
import 'offline_rule.dart';

/// Loads and saves a [HeroProgress] through a [SaveStore], so coins, upgrades,
/// stars and gear survive closing the app.
class HeroProgressStore {
  HeroProgressStore(
    this.store, {
    this.key = 'waveCombat',
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final SaveStore store;

  /// Where in the save map the progress lives, so it can share a store.
  final String key;
  final DateTime Function() _now;

  /// The saved progress (or a fresh one), with offline earnings from [rule]
  /// credited for the time since it was last saved, and saving wired to every
  /// change. The earnings wait in `pendingOfflineCoins` to be shown once.
  HeroProgress load({OfflineRule? rule}) {
    final raw = store.read()?[key];
    final progress = raw is Map
        ? HeroProgress.fromJson(raw.cast<String, dynamic>())
        : HeroProgress();
    final last = progress.lastActiveMs;
    if (rule != null && last != null) {
      final away = _now().difference(DateTime.fromMillisecondsSinceEpoch(last));
      final coins = rule.coins(progress, away);
      if (coins > 0) {
        progress.coins += coins;
        progress.pendingOfflineCoins = coins;
        progress.pendingOfflineAway = away;
      }
    }
    progress.onChanged = () => save(progress);
    save(progress);
    return progress;
  }

  /// Writes [progress], stamping the time for the next offline calculation.
  void save(HeroProgress progress) {
    progress.lastActiveMs = _now().millisecondsSinceEpoch;
    store.write({...?store.read(), key: progress.toJson()});
  }
}

/// A [SaveStore] on `shared_preferences`: one key-value save that works on
/// Android, iOS and the web, where a file store does not exist.
class PrefsSaveStore implements SaveStore {
  PrefsSaveStore._(this._prefs, this._key);

  final SharedPreferences _prefs;
  final String _key;

  /// Opens the store (this is the only async step; reads and writes after it
  /// are immediate).
  static Future<PrefsSaveStore> open([String key = 'zarvan_idle_save']) async =>
      PrefsSaveStore._(await SharedPreferences.getInstance(), key);

  @override
  Map<String, dynamic>? read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } on FormatException {
      return null;
    }
  }

  @override
  void write(Map<String, dynamic> save) {
    _prefs.setString(_key, jsonEncode(save));
  }
}
