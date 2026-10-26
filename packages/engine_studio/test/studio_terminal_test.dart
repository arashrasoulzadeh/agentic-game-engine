import 'dart:async';
import 'dart:io';

import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:engine_studio/src/project/studio_terminal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProcess implements Process {
  _FakeProcess(int code, {String out = '', String err = ''})
    : _exit = Completer<int>()..complete(code),
      stdout = Stream.value(out.codeUnits),
      stderr = Stream.value(err.codeUnits);

  final Completer<int> _exit;

  @override
  final Stream<List<int>> stdout;
  @override
  final Stream<List<int>> stderr;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  int get pid => 1;
}

void main() {
  test('TerminalSession collects stdout and exit code', () async {
    String? ran;
    final session = TerminalSession(
      command: 'echo hi',
      workingDirectory: '/proj',
      start: (exe, args, {required workingDirectory}) async {
        ran = '$exe ${args.join(' ')}';
        return _FakeProcess(0, out: 'hi\n');
      },
    );
    await session.run();
    expect(ran, '/bin/sh -c echo hi');
    expect(session.exitCode, 0);
    expect(session.transcript, contains('\$ echo hi'));
    expect(session.transcript, contains('hi'));
    expect(session.transcript, contains('[exit 0]'));
    session.dispose();
  });

  testWidgets('project terminal button opens the panel and runs a command', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('studio_term');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
    Directory('${root.path}/assets/levels').createSync(recursive: true);

    var started = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectScreen(
          project: StudioProject.open(root.path),
          useLanguageServer: false,
          terminalStarter: (exe, args, {required workingDirectory}) async {
            started++;
            expect(workingDirectory, root.path);
            return _FakeProcess(0, out: 'ok\n');
          },
        ),
      ),
    );

    expect(find.byKey(const Key('studio-terminal')), findsNothing);
    await tester.tap(find.byKey(const Key('project-terminal')));
    await tester.pump();
    expect(find.byKey(const Key('studio-terminal')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('terminal-input')), 'ls');
    await tester.tap(find.byKey(const Key('terminal-run')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(started, 1);
    expect(find.textContaining('ok'), findsOneWidget);
  });
}
