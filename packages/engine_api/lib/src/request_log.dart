import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';

/// How much detail [RequestLog] records per call.
///
/// [info] is the default: metadata only (op, timing, undo id). [debug] also
/// records arguments with [Param.secret] values replaced by `"***"`.
enum RequestLogLevel {
  info,
  debug;

  static RequestLogLevel parse(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'info':
        return RequestLogLevel.info;
      case 'debug':
        return RequestLogLevel.debug;
      default:
        throw FormatException(
          'Unknown log level "$raw" (expected info or debug).',
        );
    }
  }

  /// Maps an MCP `logging/setLevel` value onto our two-level switch.
  ///
  /// MCP uses RFC 5424 names; anything at or below `debug` enables args,
  /// everything else stays at [info].
  static RequestLogLevel fromMcp(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'debug':
        return RequestLogLevel.debug;
      case 'info':
      case 'notice':
      case 'warning':
      case 'error':
      case 'critical':
      case 'alert':
      case 'emergency':
        return RequestLogLevel.info;
      default:
        throw FormatException(
          'Unknown MCP log level "$raw".',
        );
    }
  }
}

/// Appends one JSON line per operation call to a file, rotating it at [maxBytes] and keeping [keep] old files.
///
/// Arguments and results are deliberately not recorded at [RequestLogLevel.info]: they can hold secrets and
/// whole levels, and the line is enough to answer "who changed what, when, and did it work". At
/// [RequestLogLevel.debug], arguments are included with secret params redacted.
class RequestLog {
  RequestLog(
    this.path, {
    this.maxBytes = 10 * 1024 * 1024,
    this.keep = 5,
    this.level = RequestLogLevel.info,
  });

  final String path;
  final int maxBytes;
  final int keep;
  RequestLogLevel level;

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

/// Args safe to put in a request-log line: [Param.secret] values become `"***"`.
Map<String, Object?> redactArgs(Operation? op, Map<String, Object?> args) {
  if (op == null) return Map<String, Object?>.of(args);
  final secret = {for (final p in op.params) if (p.secret) p.name};
  if (secret.isEmpty) return Map<String, Object?>.of(args);
  return {
    for (final e in args.entries)
      e.key: secret.contains(e.key) ? '***' : e.value,
  };
}
