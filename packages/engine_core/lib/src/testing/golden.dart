import 'dart:io';

/// Thrown by [expectGolden] when the text differs from the golden file. A test
/// framework reports any thrown exception as a failure.
class GoldenMismatch implements Exception {
  final String message;
  GoldenMismatch(this.message);

  @override
  String toString() => 'GoldenMismatch: $message';
}

/// Compares [actual] with the golden file at [path].
///
/// - Missing file, or the environment variable `UPDATE_GOLDENS=1`: writes
///   [actual] there (creating folders) and passes, so goldens are created and
///   refreshed by running the tests once.
/// - Otherwise throws [GoldenMismatch] naming the first differing line and
///   how to regenerate.
///
/// Review a changed golden in your diff like any other file: it is the record
/// of what the simulation produced.
void expectGolden(String path, String actual, {Map<String, String>? env}) {
  final file = File(path);
  final update = (env ?? Platform.environment)['UPDATE_GOLDENS'] == '1';
  if (update || !file.existsSync()) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(actual);
    return;
  }
  final expected = file.readAsStringSync();
  if (expected == actual) return;
  final a = expected.split('\n');
  final b = actual.split('\n');
  var line = 0;
  while (line < a.length && line < b.length && a[line] == b[line]) {
    line++;
  }
  String at(List<String> l) => line < l.length ? l[line] : '(end of file)';
  throw GoldenMismatch(
    '$path differs at line ${line + 1}:\n'
    '  golden: ${at(a)}\n'
    '  actual: ${at(b)}\n'
    'If the change is intended, regenerate with UPDATE_GOLDENS=1 and review '
    'the diff.',
  );
}
