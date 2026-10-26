import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/animation/clip_editor_screen.dart';
import 'package:engine_studio/src/animation/clip_event_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('timeline shows event markers per frame', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClipEventTimeline(
            regions: const ['a0', 'a1', 'a2'],
            frameEvents: const [
              [],
              [
                {'type': 'sfx', 'data': {'id': 'swing'}},
              ],
              [
                {'type': 'hitbox_on', 'data': {}},
                {'type': 'particle', 'data': {}},
              ],
            ],
            selectedFrame: 1,
            onSelectFrame: (_) {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('clip-timeline-mark-1-0')), findsOneWidget);
    expect(find.byKey(const Key('clip-timeline-mark-2-0')), findsOneWidget);
    expect(find.byKey(const Key('clip-timeline-mark-2-1')), findsOneWidget);
    expect(find.byKey(const Key('clip-timeline-add-0')), findsOneWidget);
  });

  testWidgets('editor timeline add attaches draft event to tapped frame', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('clip_timeline');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/attack.json';
    File(path).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'name': 'attack',
        'frameRegions': ['a0', 'a1'],
        'frameDurationSeconds': 0.1,
        'loop': false,
      }),
    );

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ClipEditorScreen(filePath: path))),
    );
    expect(find.byKey(const Key('clip-timeline')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('clip-event-type')), 'shake');
    await tester.tap(find.byKey(const Key('clip-timeline-add-1')));
    await tester.pump();

    expect(find.byKey(const Key('clip-dirty')), findsOneWidget);
    expect(find.byKey(const Key('clip-timeline-mark-1-0')), findsOneWidget);
    expect(find.byKey(const Key('clip-event-0')), findsOneWidget);
  });
}
