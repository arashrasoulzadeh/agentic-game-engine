import 'dart:async';
import 'dart:io';

import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/pub_get.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeProcess implements Process {
  _FakeProcess(int code, {String out = '', String err = '', bool hang = false})
    : _exit = hang ? Completer<int>() : (Completer<int>()..complete(code)),
      stdout = Stream.value(out.codeUnits),
      stderr = Stream.value(err.codeUnits);

  final Completer<int> _exit;
  bool killed = false;

  @override
  final Stream<List<int>> stdout;
  @override
  final Stream<List<int>> stderr;
  @override
  Future<int> get exitCode => _exit.future;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    return true;
  }

  @override
  IOSink get stdin => throw UnimplementedError();
  @override
  int get pid => 1;
}

void main() {
  group('runPubGet', () {
    test('collects stdout and stderr and reports success', () async {
      String? ran;
      String? dir;
      final r = await runPubGet(
        '/proj',
        start: (exe, args, {required workingDirectory}) async {
          ran = '$exe ${args.join(' ')}';
          dir = workingDirectory;
          return _FakeProcess(0, out: 'Resolving...\n', err: 'warn\n');
        },
      );
      expect(ran, 'flutter pub get');
      expect(dir, '/proj');
      expect(r.succeeded, isTrue);
      expect(r.output, contains('Resolving...'));
      expect(r.output, contains('warn'));
    });

    test('a failing exit code is reported with the output', () async {
      final r = await runPubGet(
        '/p',
        start: (e, a, {required workingDirectory}) async =>
            _FakeProcess(1, err: 'version solving failed'),
      );
      expect(r.succeeded, isFalse);
      expect(r.exitCode, 1);
      expect(r.output, contains('version solving failed'));
    });

    test('a command that cannot start is a result, not an exception', () async {
      final r = await runPubGet(
        '/p',
        flutter: '/no/flutter',
        start: (e, a, {required workingDirectory}) async =>
            throw const ProcessException('/no/flutter', []),
      );
      expect(r.exitCode, -1);
      expect(r.output, contains('/no/flutter pub get'));
    });

    test('a command that never ends is killed after the timeout', () async {
      final p = _FakeProcess(0, hang: true);
      final r = await runPubGet(
        '/p',
        timeout: const Duration(milliseconds: 50),
        start: (e, a, {required workingDirectory}) async => p,
      );
      expect(p.killed, isTrue);
      expect(r.exitCode, -1);
      expect(r.output, contains('Timed out'));
    });
  });

  testWidgets('the Get packages button runs pub get and shows its output', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('pub_get_ui');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    var runs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectScreen(
          project: StudioProject.open(root.path),
          useLanguageServer: false,
          pubGetStarter: (e, a, {required workingDirectory}) async {
            runs++;
            return _FakeProcess(0, out: 'Got dependencies!');
          },
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('project-pub-get')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(runs, 1);
    expect(find.byKey(const Key('pub-get-result')), findsOneWidget);
    expect(find.text('Got dependencies!'), findsOneWidget);
    expect(find.text('Packages are up to date'), findsOneWidget);
  });
}
