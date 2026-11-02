import 'dart:io';

import 'package:test/test.dart';

/// Guards two rules from CLAUDE.md that are easy to break by accident:
/// engine_core stays free of Flutter, and simulation code stays reproducible
/// (no wall clock, no unseeded randomness).
const _simulationDirs = [
  'ecs',
  'physics',
  'ai',
  'turn',
  'idle',
  'rendering',
  'ui',
  'graph',
  'command',
  'validation',
  'schema',
];

/// Known exceptions, each with the reason it is still here.
const _allowUnseededRandom = <String>{};

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.endsWith('bundled_docs.g.dart'));

String _codeOnly(File f) =>
    f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

void main() {
  test('engine_core imports nothing from Flutter or dart:ui', () {
    final offenders = [
      for (final f in _dartFiles('lib'))
        if (RegExp(
          r'''import\s+['"](package:flutter|dart:ui)''',
        ).hasMatch(_codeOnly(f)))
          f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('simulation code never reads the wall clock', () {
    final offenders = [
      for (final dir in _simulationDirs)
        if (Directory('lib/src/$dir').existsSync())
          for (final f in _dartFiles('lib/src/$dir'))
            if (_codeOnly(f).contains('DateTime.now')) f.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'Take time from the dt passed to update/step instead.',
    );
  });

  test('simulation code has no unseeded Random() outside the allowlist', () {
    final unseeded = RegExp(r'(?<![A-Za-z_])Random\(\)');
    final offenders = [
      for (final dir in _simulationDirs)
        if (Directory('lib/src/$dir').existsSync())
          for (final f in _dartFiles('lib/src/$dir'))
            if (unseeded.hasMatch(_codeOnly(f)) &&
                !_allowUnseededRandom.contains(f.path))
              f.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason: 'Use world.random, or a Random(seed) the caller can set.',
    );
  });

  test('every allowlisted file still needs its exception', () {
    final unseeded = RegExp(r'(?<![A-Za-z_])Random\(\)');
    for (final path in _allowUnseededRandom) {
      expect(
        unseeded.hasMatch(_codeOnly(File(path))),
        isTrue,
        reason: '$path no longer uses Random(): remove it from the allowlist.',
      );
    }
  });
}
