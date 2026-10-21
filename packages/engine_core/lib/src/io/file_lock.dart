import 'dart:convert';
import 'dart:io';

/// Who holds a [FileLock] and since when.
class LockInfo {
  LockInfo({required this.owner, required this.acquiredAt});

  final String owner;
  final DateTime acquiredAt;

  Map<String, dynamic> toJson() => {
    'owner': owner,
    'acquiredAt': acquiredAt.toUtc().toIso8601String(),
  };

  factory LockInfo.fromJson(Map<String, dynamic> json) => LockInfo(
    owner: json['owner'] as String,
    acquiredAt: DateTime.parse(json['acquiredAt'] as String),
  );
}

/// The outcome of [FileLock.acquire]: whether the caller now holds the lock, and who does.
class LockResult {
  const LockResult(this.acquired, this.holder);

  /// True when the caller holds the lock (newly taken, renewed, or taken over from a stale one).
  final bool acquired;

  /// The current holder; the caller itself when [acquired].
  final LockInfo holder;
}

/// An advisory lock on a file, kept as a sibling `<file>.lock` so it works on a shared folder
/// (a synced directory, a network share, a git checkout) with no server: one person edits a
/// level at a time and the others are told who has it.
///
/// It is **advisory**: nothing stops a tool that ignores it, and it is not safe against clock
/// skew between machines beyond [staleAfter]. Its job is to prevent the common accident of two
/// people editing the same level, not to be a security boundary. A lock older than [staleAfter]
/// is treated as abandoned (a crashed editor leaves one behind) and may be taken over.
class FileLock {
  FileLock(
    this.path, {
    this.staleAfter = const Duration(hours: 2),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// The file being protected; the lock file is `$path.lock`.
  final String path;
  final Duration staleAfter;
  final DateTime Function() _now;

  File get _file => File('$path.lock');

  /// The current lock, or null when unlocked. A stale or unreadable lock file is returned as
  /// null too, since nobody can be said to hold it.
  LockInfo? inspect() {
    final info = _read();
    if (info == null) return null;
    return _isStale(info) ? null : info;
  }

  /// Takes the lock for [owner]. Succeeds when the file is unlocked, already held by [owner]
  /// (which renews it), or locked by someone whose lock has gone stale.
  LockResult acquire(String owner) {
    final mine = LockInfo(owner: owner, acquiredAt: _now());
    // Create exclusively first, so two people racing for a free file cannot both win.
    try {
      _file.createSync(exclusive: true);
      _file.writeAsStringSync(jsonEncode(mine.toJson()));
      return LockResult(true, mine);
    } on PathExistsException {
      // Already locked; decide below.
    }
    final current = _read();
    if (current != null && !_isStale(current) && current.owner != owner) {
      return LockResult(false, current);
    }
    // A file that exists but cannot be read yet is usually someone mid-way through creating
    // it (the exclusive create and the write are two steps): back off rather than steal it.
    if (current == null && _justCreated()) {
      return LockResult(false, LockInfo(owner: 'someone', acquiredAt: _now()));
    }
    _file.writeAsStringSync(jsonEncode(mine.toJson()));
    return LockResult(true, mine);
  }

  /// Releases the lock if [owner] holds it (or it is stale/unreadable). Returns false, and
  /// leaves the lock alone, when someone else holds a live one - unless [force].
  bool release(String owner, {bool force = false}) {
    final current = _read();
    if (current == null) {
      if (_file.existsSync()) _file.deleteSync();
      return true;
    }
    if (!force && current.owner != owner && !_isStale(current)) return false;
    _file.deleteSync();
    return true;
  }

  LockInfo? _read() {
    try {
      if (!_file.existsSync()) return null;
      final json = jsonDecode(_file.readAsStringSync());
      return json is Map<String, dynamic> ? LockInfo.fromJson(json) : null;
    } on Object {
      return null;
    }
  }

  bool _justCreated() {
    try {
      return DateTime.now().difference(_file.lastModifiedSync()) <
          const Duration(seconds: 3);
    } on FileSystemException {
      return false;
    }
  }

  bool _isStale(LockInfo info) =>
      _now().difference(info.acquiredAt) > staleAfter;
}

/// A name for the person at this machine - `user@host` - to use as a lock owner.
String lockOwner({Map<String, String>? env, String? hostname}) {
  final e = env ?? Platform.environment;
  final user = e['USER'] ?? e['USERNAME'] ?? 'someone';
  return '$user@${hostname ?? Platform.localHostname}';
}
