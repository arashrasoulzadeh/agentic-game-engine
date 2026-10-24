import 'dart:convert';
import 'dart:io';

/// Appends one JSON line per operation call to a file, rotating it at [maxBytes] and keeping [keep] old files.
///
/// Arguments and results are deliberately not recorded: they can hold secrets and whole levels, and the line is
/// enough to answer "who changed what, when, and did it work".
class RequestLog {
  RequestLog(this.path, {this.maxBytes = 10 * 1024 * 1024, this.keep = 5});

  final String path;
  final int maxBytes;
  final int keep;

  void write(Map<String, Object?> entry) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    if (file.existsSync() && file.lengthSync() >= maxBytes) _rotate();
    file.writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
  }

  void _rotate() {
    final oldest = File('$path.$keep');
    if (oldest.existsSync()) oldest.deleteSync();
    for (var i = keep - 1; i >= 1; i--) {
      final f = File('$path.$i');
      if (f.existsSync()) f.renameSync('$path.${i + 1}');
    }
    File(path).renameSync('$path.1');
  }
}
