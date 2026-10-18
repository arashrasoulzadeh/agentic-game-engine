import 'dart:io';

import 'package:engine_studio/src/prefs/shortcuts.dart';
import 'package:engine_studio/src/prefs/strings.dart';
import 'package:engine_studio/src/project/project_screen.dart';
import 'package:engine_studio/src/project/studio_project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('strings'));
  tearDown(() {
    StudioStrings.use('en');
    dir.deleteSync(recursive: true);
  });

  test('English is the default and an unknown key shows as itself', () {
    expect(StudioStrings.t('project.close'), 'Close');
    expect(StudioStrings.t('no.such.key'), 'no.such.key');
  });

  test('a locale file overrides only the keys it translates', () {
    File(
      '${dir.path}/fr.json',
    ).writeAsStringSync('{"project.close":"Fermer","bogus":"x"}');
    StudioStrings.use('fr', localesDir: dir);
    expect(StudioStrings.t('project.close'), 'Fermer');
    expect(StudioStrings.t('project.newGraph'), 'New graph');
    expect(StudioStrings.t('bogus'), 'bogus');
  });

  test('a missing or broken locale file leaves English', () {
    StudioStrings.use('de', localesDir: dir);
    expect(StudioStrings.t('project.close'), 'Close');
    File('${dir.path}/es.json').writeAsStringSync('{ nope');
    StudioStrings.use('es', localesDir: dir);
    expect(StudioStrings.t('project.close'), 'Close');
  });

  test('right-to-left locales are reported', () {
    StudioStrings.use('fa');
    expect(StudioStrings.isRtl, isTrue);
    StudioStrings.use('en');
    expect(StudioStrings.isRtl, isFalse);
  });

  test('the locale comes from the prefs file, defaulting to en', () {
    final prefs = File('${dir.path}/studio_prefs.json');
    expect(loadLocale(prefs), 'en');
    prefs.writeAsStringSync('{"locale":"fr"}');
    expect(loadLocale(prefs), 'fr');
    prefs.writeAsStringSync('garbage');
    expect(loadLocale(prefs), 'en');
  });

  testWidgets('the project window shows the translated tooltips', (
    tester,
  ) async {
    final root = Directory.systemTemp.createTempSync('strings_proj');
    addTearDown(() => root.deleteSync(recursive: true));
    File('${root.path}/pubspec.yaml').writeAsStringSync('name: g\n');
    Directory('${root.path}/assets/levels').createSync(recursive: true);
    File(
      '${dir.path}/fr.json',
    ).writeAsStringSync('{"project.problems":"Problèmes"}');
    StudioStrings.use('fr', localesDir: dir);
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectScreen(
          project: StudioProject.open(root.path),
          useLanguageServer: false,
        ),
      ),
    );
    expect(find.byTooltip('Problèmes'), findsOneWidget);
    expect(find.byTooltip('New graph'), findsOneWidget);
  });
}
