import 'dart:io';

import 'package:path/path.dart' as p;

/// Finds the Dart binary the language server should run. Apps launched from Finder
/// do not inherit the shell's PATH, so the search covers the places a Flutter or
/// Dart SDK is usually installed, not only PATH.
///
/// Order: the DART_SDK or FLUTTER_ROOT environment variables, then common install
/// locations, then PATH. Returns null when none is found, so the caller can say so.
String? findDartBinary({
  Map<String, String>? environment,
  String? home,
  bool Function(String path)? exists,
}) {
  final env = environment ?? Platform.environment;
  final userHome = home ?? env['HOME'] ?? '';
  final present = exists ?? (path) => File(path).existsSync();

  final candidates = <String>[
    if (env['DART_SDK'] != null) p.join(env['DART_SDK']!, 'bin', 'dart'),
    if (env['FLUTTER_ROOT'] != null)
      p.join(env['FLUTTER_ROOT']!, 'bin', 'cache', 'dart-sdk', 'bin', 'dart'),
    p.join(
      userHome,
      'develop',
      'flutter',
      'bin',
      'cache',
      'dart-sdk',
      'bin',
      'dart',
    ),
    p.join(userHome, 'flutter', 'bin', 'cache', 'dart-sdk', 'bin', 'dart'),
    '/opt/homebrew/bin/dart',
    '/usr/local/bin/dart',
    '/opt/homebrew/opt/dart/libexec/bin/dart',
    for (final dir in (env['PATH'] ?? '').split(':'))
      if (dir.isNotEmpty) p.join(dir, 'dart'),
  ];
  for (final candidate in candidates) {
    if (present(candidate)) return candidate;
  }
  return null;
}
