import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// How bad an analyzer finding is. An error means the code will not compile or
/// will fail at runtime; a warning means it probably works but is suspect.
enum AnalysisSeverity { error, warning, info }

/// One finding from `dart analyze`: where it is, and what the analyzer said.
class AnalysisIssue {
  final AnalysisSeverity severity;
  final String code;
  final String file;
  final int line;
  final int column;
  final String message;

  const AnalysisIssue({
    required this.severity,
    required this.code,
    required this.file,
    required this.line,
    required this.column,
    required this.message,
  });

  @override
  String toString() => '${p.basename(file)}:$line:$column: $message';
}

/// Parses `dart analyze --format=machine` output. Each finding is one line of
/// `SEVERITY|TYPE|CODE|FILE|LINE|COLUMN|LENGTH|MESSAGE`. Lines that do not match
/// are skipped, so a progress or banner line never breaks the list.
List<AnalysisIssue> parseAnalyzerOutput(String output) {
  final issues = <AnalysisIssue>[];
  for (final line in const LineSplitter().convert(output)) {
    final fields = line.split('|');
    if (fields.length < 8) continue;
    final severity = switch (fields[0]) {
      'ERROR' => AnalysisSeverity.error,
      'WARNING' => AnalysisSeverity.warning,
      'INFO' => AnalysisSeverity.info,
      _ => null,
    };
    final lineNumber = int.tryParse(fields[4]);
    final column = int.tryParse(fields[5]);
    if (severity == null || lineNumber == null || column == null) continue;
    issues.add(
      AnalysisIssue(
        severity: severity,
        code: fields[2],
        file: fields[3],
        line: lineNumber,
        column: column,
        // The message can itself contain '|', so everything after the 7th field is kept.
        message: fields.sublist(7).join('|'),
      ),
    );
  }
  return issues;
}

/// Runs an external command. Injected so tests can supply the analyzer's output
/// instead of running the analyzer.
typedef CommandRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments,
      String workingDirectory,
    );

/// Analyzes a project and reports its problems. Uses the Dart analyzer, which
/// reports compile errors (type and syntax) as well as lints, so one run is the
/// compile check.
class ProjectAnalyzer {
  final String dart;
  final CommandRunner _run;

  ProjectAnalyzer({this.dart = 'dart', CommandRunner? run})
    : _run = run ?? _defaultRun;

  static Future<ProcessResult> _defaultRun(
    String executable,
    List<String> arguments,
    String workingDirectory,
  ) => Process.run(executable, arguments, workingDirectory: workingDirectory);

  /// Analyzes [projectRoot]'s `lib` folder. Findings for files outside `lib` are
  /// not reported here.
  Future<List<AnalysisIssue>> analyze(String projectRoot) async {
    final result = await _run(dart, [
      'analyze',
      '--format=machine',
      'lib',
    ], projectRoot);
    return parseAnalyzerOutput('${result.stdout}');
  }
}
