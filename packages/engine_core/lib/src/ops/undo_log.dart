import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'files.dart';
import 'result.dart';

/// One recorded write: which operation did it and the full before/after text (or base64 bytes) of every
/// file it touched, so it can be undone and redone without git.
class UndoEntry {
  UndoEntry({
    required this.id,
    required this.op,
    required this.actor,
    required this.at,
    required this.files,
    this.undone = false,
  });

  final String id;
  final String op;
  final String actor;
  final DateTime at;
  final List<FileChange> files;

  /// True while the entry is undone (so `undo.redo` can re-apply it).
  bool undone;

  Map<String, Object?> toJson() => {
    'id': id,
    'op': op,
    'actor': actor,
    'at': at.toUtc().toIso8601String(),
    'undone': undone,
    'files': [
      for (final f in files)
        {
          'path': f.path,
          'before': f.before,
          'after': f.after,
          if (f.beforeBytes != null)
            'beforeBytes': base64Encode(f.beforeBytes!),
          if (f.afterBytes != null) 'afterBytes': base64Encode(f.afterBytes!),
        },
    ],
  };

  factory UndoEntry.fromJson(Map<String, dynamic> j) => UndoEntry(
    id: j['id'] as String,
    op: j['op'] as String,
    actor: j['actor'] as String? ?? '',
    at: DateTime.parse(j['at'] as String),
    undone: j['undone'] as bool? ?? false,
    files: [
      for (final f in (j['files'] as List).cast<Map<String, dynamic>>())
        FileChange(
          path: f['path'] as String,
          before: f['before'] as String?,
          after: f['after'] as String?,
          beforeBytes: f['beforeBytes'] is String
              ? Uint8List.fromList(base64Decode(f['beforeBytes'] as String))
              : null,
          afterBytes: f['afterBytes'] is String
              ? Uint8List.fromList(base64Decode(f['afterBytes'] as String))
              : null,
        ),
    ],
  );

  /// Summary for listings (no file contents).
  Map<String, Object?> summaryJson() => {
    'id': id,
    'op': op,
    'actor': actor,
    'at': at.toUtc().toIso8601String(),
    'undone': undone,
    'files': [for (final f in files) f.path],
  };
}

String sha256Of(String? text) =>
    text == null ? 'none' : crypto.sha256.convert(utf8.encode(text)).toString();

String sha256OfBytes(Uint8List? data) =>
    data == null ? 'none' : crypto.sha256.convert(data).toString();

/// The write journal kept inside the project at `.studio/undo/`: one JSON file per write, the last [keep] kept.
///
/// Entries are written **before** the files they describe change, so a crash mid-write leaves a record that can
/// restore the old content.
class UndoLog {
  UndoLog({
    required this.files,
    required this.projectRoot,
    required this.clock,
    this.keep = 100,
  });

  final ProjectFiles files;
  final String projectRoot;
  final DateTime Function() clock;
  final int keep;

  String get _dir => p.join(projectRoot, '.studio', 'undo');

  List<String> _paths() =>
      files.list(_dir).where((f) => f.endsWith('.json')).toList()..sort();

  /// Records [changes] made by [op] and prunes the journal. Returns the new entry's id.
  String record(String op, String actor, List<FileChange> changes) {
    final names = _paths();
    var next = 1;
    if (names.isNotEmpty) {
      final last = p.basename(names.last).split('-').first;
      next = (int.tryParse(last) ?? names.length) + 1;
    }
    final at = clock().toUtc();
    final stamp = at
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .split('.')
        .first;
    final id = '${next.toString().padLeft(6, '0')}-${stamp}Z-$op';
    final entry = UndoEntry(
      id: id,
      op: op,
      actor: actor,
      at: at,
      files: changes,
    );
    files.writeAtomic(p.join(_dir, '$id.json'), jsonEncode(entry.toJson()));
    final all = _paths();
    for (final old in all.take((all.length - keep).clamp(0, all.length))) {
      files.delete(old);
    }
    return id;
  }

  /// Newest first, at most [limit].
  List<UndoEntry> list({int limit = 50}) {
    final out = <UndoEntry>[];
    for (final path in _paths().reversed.take(limit)) {
      final text = files.read(path);
      if (text == null) continue;
      try {
        out.add(UndoEntry.fromJson(jsonDecode(text) as Map<String, dynamic>));
      } on Object {
        // A damaged journal file is skipped, not fatal.
      }
    }
    return out;
  }

  UndoEntry? find(String id) {
    final text = files.read(p.join(_dir, '$id.json'));
    if (text == null) return null;
    return UndoEntry.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  /// Flags [id] as undone or redone.
  void mark(String id, {required bool undone}) {
    final e = find(id);
    if (e == null) return;
    e.undone = undone;
    files.writeAtomic(p.join(_dir, '$id.json'), jsonEncode(e.toJson()));
  }
}
