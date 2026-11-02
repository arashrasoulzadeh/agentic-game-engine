import 'package:engine_studio/src/project/git_panel.dart';
import 'package:engine_studio/src/project/git_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _panel({
  required Map<String, GitChange> changes,
  required GitRunner runner,
  List<String>? opened,
  void Function()? onRefresh,
}) => MaterialApp(
  home: Scaffold(
    body: GitPanel(
      projectRoot: '/p',
      changes: changes,
      gitRunner: runner,
      onClose: () {},
      onRefresh: onRefresh ?? () {},
      onOpenFile: (path) => opened?.add(path),
    ),
  ),
);

void main() {
  testWidgets('shows the empty state when nothing changed', (tester) async {
    await tester.pumpWidget(
      _panel(changes: const {}, runner: (a, d) async => ''),
    );
    expect(find.byKey(const Key('git-panel-empty')), findsOneWidget);
  });

  testWidgets('tapping a file opens it and shows its diff', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _panel(
        changes: const {'a.dart': GitChange.modified},
        opened: opened,
        runner: (args, dir) async =>
            args.first == 'diff' && args[1] == '--' ? '+added line\n' : '',
      ),
    );
    await tester.tap(find.byKey(const Key('git-panel-file-a.dart')));
    await tester.pumpAndSettle();
    expect(opened, ['a.dart']);
    expect(find.textContaining('+added line'), findsOneWidget);
  });

  testWidgets('commit runs add then commit, clears the message, refreshes', (
    tester,
  ) async {
    final calls = <List<String>>[];
    var refreshed = 0;
    await tester.pumpWidget(
      _panel(
        changes: const {'a.dart': GitChange.modified},
        onRefresh: () => refreshed++,
        runner: (args, dir) async {
          calls.add(args);
          return args.first == 'commit' ? '[main 1] done\n' : '';
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key('git-commit-message')),
      'my message',
    );
    await tester.tap(find.byKey(const Key('git-commit')));
    await tester.pumpAndSettle();
    expect(calls, [
      ['add', '-A'],
      ['commit', '-m', 'my message'],
    ]);
    expect(refreshed, 1);
    expect(find.text('[main 1] done'), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(const Key('git-commit-message')),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('an empty message is refused without calling git', (
    tester,
  ) async {
    var ran = false;
    await tester.pumpWidget(
      _panel(
        changes: const {'a.dart': GitChange.modified},
        runner: (args, dir) async {
          ran = true;
          return '';
        },
      ),
    );
    await tester.tap(find.byKey(const Key('git-commit')));
    await tester.pumpAndSettle();
    expect(ran, isFalse);
    expect(find.text('Commit message is empty.'), findsOneWidget);
  });
}
