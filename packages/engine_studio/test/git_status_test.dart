import 'dart:io';

import 'package:engine_studio/src/project/git_status.dart';
import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseGitStatus', () {
    test('maps each state to a change', () {
      final m = parseGitStatus(
        ' M lib/a.dart\n'
        'M  lib/b.dart\n'
        'A  new.dart\n'
        ' D gone.dart\n'
        'D  gone2.dart\n'
        '?? scratch.txt\n'
        'R  old.dart -> renamed.dart\n'
        'UU clash.dart\n'
        'AA both.dart\n',
      );
      expect(m['lib/a.dart'], GitChange.modified);
      expect(m['lib/b.dart'], GitChange.modified);
      expect(m['new.dart'], GitChange.added);
      expect(m['gone.dart'], GitChange.deleted);
      expect(m['gone2.dart'], GitChange.deleted);
      expect(m['scratch.txt'], GitChange.untracked);
      expect(m['renamed.dart'], GitChange.renamed);
      expect(m.containsKey('old.dart'), isFalse);
      expect(m['clash.dart'], GitChange.conflicted);
      expect(m['both.dart'], GitChange.conflicted);
    });

    test('unquotes odd paths, trims untracked folders, skips junk', () {
      final m = parseGitStatus(
        '?? "my file.txt"\n?? build/\n\nx\n!! ignored.log\n',
      );
      expect(m['my file.txt'], GitChange.untracked);
      expect(m['build'], GitChange.untracked);
      expect(m.length, 2);
    });

    test('badges are one letter', () {
      expect({for (final c in GitChange.values) c.badge.length}, {1});
    });
  });

  group('readGitStatus', () {
    test('not a repository (or no git) means no changes', () async {
      expect(await readGitStatus('/x', run: (a, d) async => null), isEmpty);
    });

    test(
      'paths are rebased when the project is a subfolder of the repository',
      () async {
        final result = await readGitStatus(
          '/repo/games/mine',
          run: (args, dir) async => args.first == 'rev-parse'
              ? '/repo\n'
              : ' M games/mine/assets/levels/a.json\n M games/other/x.dart\n?? README.md\n',
        );
        expect(result, {'assets/levels/a.json': GitChange.modified});
      },
    );

    test(
      'a real repository: a new file shows as untracked, then a committed edit as modified',
      () async {
        final dir = Directory.systemTemp.createTempSync('git_status_real');
        addTearDown(() => dir.deleteSync(recursive: true));
        Future<void> git(List<String> a) async {
          final r = await Process.run('git', [
            '-c',
            'user.name=t',
            '-c',
            'user.email=t@t',
            ...a,
          ], workingDirectory: dir.path);
          expect(r.exitCode, 0, reason: '${r.stderr}');
        }

        await git(['init', '-q']);
        File('${dir.path}/a.txt').writeAsStringSync('one');
        expect(await readGitStatus(dir.path), {'a.txt': GitChange.untracked});
        await git(['add', '.']);
        await git(['commit', '-q', '-m', 'x']);
        expect(await readGitStatus(dir.path), isEmpty);
        File('${dir.path}/a.txt').writeAsStringSync('two');
        expect(await readGitStatus(dir.path), {'a.txt': GitChange.modified});
      },
    );
  });

  test('folderHasChanges looks inside the folder only', () {
    const c = {'assets/levels/a.json': GitChange.modified};
    expect(folderHasChanges(c, 'assets'), isTrue);
    expect(folderHasChanges(c, 'assets/levels'), isTrue);
    expect(folderHasChanges(c, 'asset'), isFalse);
    expect(folderHasChanges(c, 'lib'), isFalse);
  });

  testWidgets(
    'the file tree marks changed files and the folders that hold them',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('git_tree');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
      Directory('${root.path}/assets/levels').createSync(recursive: true);
      File(
        '${root.path}/assets/levels/a.json',
      ).writeAsStringSync('{"entities": []}');
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectScreen(
            project: StudioProject.open(root.path),
            useLanguageServer: false,
            gitRunner: (args, dir) async {
              calls++;
              return args.first == 'rev-parse'
                  ? '${root.path}\n'
                  : ' M assets/levels/a.json\n?? pubspec.yaml\n';
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('git-pubspec.yaml')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('git-pubspec.yaml'))).data,
        '?',
      );
      expect(
        find.byKey(const Key('git-dir-assets')),
        findsOneWidget,
        reason: 'the collapsed folder shows where the change is',
      );

      await tester.tap(find.byKey(const Key('file-assets')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('file-assets/levels')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const Key('git-assets/levels/a.json')))
            .data,
        'M',
      );

      final before = calls;
      await tester.tap(find.byKey(const Key('project-git-refresh')));
      await tester.pumpAndSettle();
      expect(calls, greaterThan(before));
    },
  );
}
