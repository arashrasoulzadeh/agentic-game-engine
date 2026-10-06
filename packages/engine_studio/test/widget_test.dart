import 'dart:io';

import 'package:engine_studio/src/project/project_open_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('studio_screen'));
  tearDown(() => root.deleteSync(recursive: true));

  testWidgets('shows the reason a folder cannot be opened', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectOpenScreen(onOpened: (_, _) => fail('should not open')),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('project-path')),
      '${root.path}/missing',
    );
    await tester.tap(find.byKey(const Key('open-project')));
    await tester.pump();

    expect(find.byKey(const Key('open-error')), findsOneWidget);
    expect(find.textContaining('does not exist'), findsOneWidget);
  });

  testWidgets('opens a valid project and reports it', (tester) async {
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: my_game\n');
    Directory('${root.path}/assets/levels').createSync(recursive: true);

    StudioProject? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectOpenScreen(onOpened: (_, project) => opened = project),
      ),
    );
    await tester.enterText(find.byKey(const Key('project-path')), root.path);
    await tester.tap(find.byKey(const Key('open-project')));
    await tester.pump();

    expect(opened, isNotNull);
    expect(find.byKey(const Key('open-error')), findsNothing);
  });
}
