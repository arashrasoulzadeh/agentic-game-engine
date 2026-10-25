// Regenerates lib/src/ops/bundled_docs.g.dart from the curated remote index.
//
//   dart run tool/gen_bundled_docs.dart
//
// Reads ../../docs/<page> for each entry in kRemoteDocsPages (engine_ops.dart).
// Run whenever those curated pages change; CI / local tests assert the file is current.

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:engine_core/engine_core_ops.dart' show kRemoteDocsPages;

void main() {
  final packageRoot = Directory.current.path;
  final docsRoot = p.normalize(p.join(packageRoot, '..', '..', 'docs'));
  final outPath = p.join(packageRoot, 'lib', 'src', 'ops', 'bundled_docs.g.dart');

  final buf = StringBuffer()
    ..writeln('// GENERATED — do not edit.')
    ..writeln('// dart run tool/gen_bundled_docs.dart')
    ..writeln()
    ..writeln('/// Curated markdown bodies for [kRemoteDocsPages] (engine.docs offline).')
    ..writeln('const kBundledDocs = <String, String>{');

  for (final rel in kRemoteDocsPages) {
    final file = File(p.join(docsRoot, rel));
    if (!file.existsSync()) {
      stderr.writeln('Missing docs/$rel');
      exit(1);
    }
    final raw = file.readAsStringSync();
    buf
      ..writeln("  '$rel': ${_dartString(raw)},")
      ..writeln();
  }
  buf.writeln('};');

  File(outPath).writeAsStringSync(buf.toString());
  stdout.writeln(
    'Wrote ${kRemoteDocsPages.length} pages '
    '(${File(outPath).lengthSync()} bytes) → $outPath',
  );
}

String _dartString(String s) {
  final escaped = s
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'", r"\'");
  return "'''$escaped'''";
}
