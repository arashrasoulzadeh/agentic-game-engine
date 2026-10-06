import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('code_editor');
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: my_game\n');
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    Directory('${root.path}/lib').createSync();
  });
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('shows the file, marks it dirty on edit, and saves it to disk', (
    tester,
  ) async {
    final path = '${root.path}/lib/main.dart';
    File(path).writeAsStringSync('void main() {}\n');
    await tester.pumpWidget(
      MaterialApp(home: CodeEditorScreen(filePath: path)),
    );

    expect(find.text('void main() {}\n'), findsOneWidget);
    expect(find.byKey(const Key('code-dirty')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('code-text')),
      'void main() { print(1); }\n',
    );
    await tester.pump();
    expect(find.byKey(const Key('code-dirty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('code-save')));
    await tester.pump();
    expect(find.byKey(const Key('code-dirty')), findsNothing);
    expect(File(path).readAsStringSync(), 'void main() { print(1); }\n');
    expect(File('$path.tmp').existsSync(), isFalse);
  });

  testWidgets('a file that cannot be written reports the error and stays dirty', (
    tester,
  ) async {
    final path = '${root.path}/lib/main.dart';
    File(path).writeAsStringSync('a');
    await tester.pumpWidget(
      MaterialApp(home: CodeEditorScreen(filePath: path)),
    );
    // Removing the folder makes the temp-file write fail, the way a read-only or
    // vanished project would.
    root.deleteSync(recursive: true);
    await tester.enterText(find.byKey(const Key('code-text')), 'b');
    await tester.pump();
    await tester.tap(find.byKey(const Key('code-save')));
    await tester.pump();

    expect(find.byKey(const Key('code-error')), findsOneWidget);
    expect(find.byKey(const Key('code-dirty')), findsOneWidget);
    root = Directory.systemTemp.createTempSync('code_editor_again');
  });

  test(
    'codeFiles lists the Dart source under lib/, sorted, and nothing else',
    () {
      File('${root.path}/lib/zeta.dart').writeAsStringSync('');
      File('${root.path}/lib/alpha.dart').writeAsStringSync('');
      File('${root.path}/lib/notes.txt').writeAsStringSync('');
      File('${root.path}/assets/levels/a.json').writeAsStringSync('{}');

      expect(StudioProject.open(root.path).codeFiles(), [
        'lib/alpha.dart',
        'lib/zeta.dart',
      ]);
    },
  );
}
