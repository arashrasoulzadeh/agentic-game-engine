import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/prefs/recent_projects.dart';
import 'package:engine_studio/src/project/project_open_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('rememberRecentProject prepends and caps the list', () {
    final dir = Directory.systemTemp.createTempSync('recent_prefs');
    addTearDown(() => dir.deleteSync(recursive: true));
    final prefs = File('${dir.path}/studio_prefs.json');
    rememberRecentProject('${dir.path}/a', prefs);
    rememberRecentProject('${dir.path}/b', prefs);
    rememberRecentProject('${dir.path}/a', prefs);
    final recent = loadRecentProjects(prefs);
    expect(recent.first, p.normalize(p.absolute('${dir.path}/a')));
    expect(recent.where((e) => e.endsWith('/a')).length, 1);
    expect(recent.length, 2);
  });

  testWidgets('open screen lists recent projects and opens one', (tester) async {
    final dir = Directory.systemTemp.createTempSync('recent_ui');
    addTearDown(() => dir.deleteSync(recursive: true));
    final game = Directory('${dir.path}/game')..createSync();
    File('${game.path}/pubspec.yaml').writeAsStringSync('name: g\n');
    Directory('${game.path}/assets/levels').createSync(recursive: true);
    final prefs = File('${dir.path}/studio_prefs.json')
      ..writeAsStringSync(
        jsonEncode({
          'recentProjects': [game.path],
        }),
      );

    StudioProject? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectOpenScreen(
          prefsFile: prefs,
          onOpened: (_, project) => opened = project,
        ),
      ),
    );
    expect(find.byKey(const Key('recent-projects')), findsOneWidget);
    await tester.tap(find.byKey(const Key('recent-0')));
    await tester.pump();
    expect(opened?.root, p.normalize(p.absolute(game.path)));
  });
}
