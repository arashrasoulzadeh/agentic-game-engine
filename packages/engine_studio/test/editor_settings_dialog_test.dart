import 'dart:io';

import 'package:engine_studio/src/code/code_editor_screen.dart';
import 'package:engine_studio/src/code/editor_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late String path;
  setUp(() {
    root = Directory.systemTemp.createTempSync('editor_settings_dialog');
    path = '${root.path}/a.txt';
    File(path).writeAsStringSync('hello\n');
  });
  tearDown(() => root.deleteSync(recursive: true));

  Future<void> openEditor(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: CodeEditorScreen(
        filePath: path,
        projectRoot: root.path,
        useLanguageServer: false,
      ),
    ),
  );

  testWidgets('loads saved settings on open and applies the font size', (
    tester,
  ) async {
    EditorSettingsStore(root.path).write(const EditorSettings(fontSize: 20));
    await openEditor(tester);
    final field = tester.widget<TextField>(find.byKey(const Key('code-text')));
    expect(field.style!.fontSize, 20);
  });

  testWidgets(
    'changing settings in the dialog saves them and they persist on reopen',
    (tester) async {
      await openEditor(tester);
      await tester.tap(find.byKey(const Key('code-settings')));
      await tester.pump();

      final tabWidthSlider = tester.widget<Slider>(
        find.byKey(const Key('settings-tab-width')),
      );
      tabWidthSlider.onChanged!(4);
      await tester.pump();

      await tester.tap(find.byKey(const Key('settings-format-on-save')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pump();

      final saved = EditorSettingsStore(root.path).read();
      expect(saved.tabWidth, 4);
      expect(saved.formatOnSave, isTrue);
    },
  );

  testWidgets('cancelling the dialog keeps the previous settings', (
    tester,
  ) async {
    EditorSettingsStore(root.path).write(const EditorSettings(fontSize: 15));
    await openEditor(tester);
    await tester.tap(find.byKey(const Key('code-settings')));
    await tester.pump();

    final slider = tester.widget<Slider>(
      find.byKey(const Key('settings-font-size')),
    );
    slider.onChanged!(28);
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pump();

    final saved = EditorSettingsStore(root.path).read();
    expect(saved.fontSize, 15);
  });
}
