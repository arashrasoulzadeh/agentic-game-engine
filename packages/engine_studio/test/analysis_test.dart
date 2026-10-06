import 'dart:io';

import 'package:engine_studio/src/code/analysis.dart';
import 'package:flutter_test/flutter_test.dart';

const _machine = '''
WARNING|STATIC_WARNING|UNUSED_IMPORT|/game/lib/a.dart|4|8|9|Unused import: 'dart:ui'.
ERROR|COMPILE_TIME_ERROR|UNDEFINED_IDENTIFIER|/game/lib/b.dart|12|3|5|Undefined name 'hero'
INFO|HINT|PREFER_CONST|/game/lib/c.dart|1|1|2|a | b keeps its pipe
Analyzing lib...
''';

void main() {
  test('parses each finding with its severity, code, place, and message', () {
    final issues = parseAnalyzerOutput(_machine);
    expect(issues, hasLength(3));

    expect(issues[0].severity, AnalysisSeverity.warning);
    expect(issues[0].code, 'UNUSED_IMPORT');
    expect(issues[0].line, 4);
    expect(issues[0].message, "Unused import: 'dart:ui'.");

    expect(issues[1].severity, AnalysisSeverity.error);
    expect(issues[1].file, '/game/lib/b.dart');
    expect(issues[1].column, 3);
  });

  test('keeps a pipe that appears inside a message', () {
    final issues = parseAnalyzerOutput(_machine);
    expect(issues[2].message, 'a | b keeps its pipe');
  });

  test('skips banner and malformed lines rather than failing', () {
    expect(
      parseAnalyzerOutput('Analyzing lib...\nnot|enough|fields\n'),
      isEmpty,
    );
  });

  test('a finding reads as file:line:column and its message', () {
    final issue = parseAnalyzerOutput(_machine)[1];
    expect(issue.toString(), 'b.dart:12:3: Undefined name \'hero\'');
  });

  test('the analyzer is run on the project with machine output', () async {
    String? seenExecutable;
    List<String>? seenArguments;
    String? seenDirectory;
    final analyzer = ProjectAnalyzer(
      dart: '/sdk/dart',
      run: (executable, arguments, directory) async {
        seenExecutable = executable;
        seenArguments = arguments;
        seenDirectory = directory;
        return ProcessResult(0, 0, _machine, '');
      },
    );

    final issues = await analyzer.analyze('/game');
    expect(seenExecutable, '/sdk/dart');
    expect(seenArguments, ['analyze', '--format=machine', 'lib']);
    expect(seenDirectory, '/game');
    expect(issues, hasLength(3));
  });
}
