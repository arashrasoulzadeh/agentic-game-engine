import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/animation/clip_editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('clip_editor');
    path = '${dir.path}/attack.json';
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'name': 'attack',
        'frameRegions': ['a0', 'a1'],
        'frameDurationSeconds': 0.1,
        'loop': false,
      }),
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> open(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ClipEditorScreen(filePath: path))),
      );

  test('looksLikeAnimationClipFile accepts clip JSON only', () {
    expect(looksLikeAnimationClipFile(path), isTrue);
    final other = File('${dir.path}/level.json')
      ..writeAsStringSync('{"width":1,"height":1,"entities":[]}');
    expect(looksLikeAnimationClipFile(other.path), isFalse);
  });

  testWidgets('loads frames and can add an event then save', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('clip-editor')), findsOneWidget);
    expect(find.byKey(const Key('clip-frame-0')), findsOneWidget);
    expect(find.byKey(const Key('clip-frame-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('clip-frame-1')));
    await tester.pump();

    await tester.enterText(find.byKey(const Key('clip-event-type')), 'sfx');
    await tester.enterText(
      find.byKey(const Key('clip-event-data')),
      '{"id":"swing"}',
    );
    await tester.tap(find.byKey(const Key('clip-add-event')));
    await tester.pump();

    expect(find.byKey(const Key('clip-dirty')), findsOneWidget);
    expect(find.byKey(const Key('clip-event-0')), findsOneWidget);

    await tester.tap(find.byKey(const Key('clip-save')));
    await tester.pump();

    final saved = jsonDecode(File(path).readAsStringSync()) as Map;
    expect(saved['frameEvents'], isA<List>());
    expect(saved['frameEvents'][1][0]['type'], 'sfx');
    expect(saved['frameEvents'][1][0]['data']['id'], 'swing');
  });

  testWidgets('add frame appends a region', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('clip-region-input')), 'a2');
    await tester.tap(find.byKey(const Key('clip-add-frame')));
    await tester.pump();
    expect(find.byKey(const Key('clip-frame-2')), findsOneWidget);

    await tester.tap(find.byKey(const Key('clip-save')));
    await tester.pump();
    final saved = jsonDecode(File(path).readAsStringSync()) as Map;
    expect(saved['frameRegions'], ['a0', 'a1', 'a2']);
  });

  testWidgets('apply pivot writes frameOffsetsY', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('clip-frame-0')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('clip-offset-y')), '-4');
    await tester.tap(find.byKey(const Key('clip-apply-pivot')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('clip-save')));
    await tester.pump();

    final saved = jsonDecode(File(path).readAsStringSync()) as Map;
    expect(saved['frameOffsetsY'], [-4, 0]);
  });
}
