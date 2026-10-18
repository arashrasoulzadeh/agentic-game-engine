import 'dart:convert';
import 'dart:io';

import 'package:engine_studio/src/bootstrap/bootstrap_screen.dart';
import 'package:engine_studio/src/bootstrap/bootstrapper.dart';
import 'package:engine_studio/src/bootstrap/update_config.dart';
import 'package:engine_studio/src/project/project_open_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_release_server.dart';

Future<void> _show(WidgetTester tester, Bootstrapper boot) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: BootstrapScreen(bootstrapper: boot)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'lists what is on offer with its size, and installs nothing until accepted',
    (tester) async {
      final r = await tester.runAsync(bootstrapRig) as dynamic;
      r.server.put('templates', 'T' * 2048);
      r.server.put('brushes', 'B');
      await tester.runAsync(() async {});
      await _show(tester, r.boot as Bootstrapper);

      expect(find.byKey(const Key('bootstrap-item-templates')), findsOneWidget);
      expect(find.textContaining('New · 2.0 KB'), findsOneWidget);
      expect(find.textContaining('New · 1 B'), findsOneWidget);
      final install = tester.widget<FilledButton>(
        find.byKey(const Key('bootstrap-install')),
      );
      expect(install.onPressed, isNull, reason: 'nothing accepted yet');
      expect(r.server.downloads, isEmpty);
    },
  );

  testWidgets(
    'accepting an item and pressing Install downloads and verifies it',
    (tester) async {
      final r = await tester.runAsync(bootstrapRig) as dynamic;
      r.server.put('templates', 'T1');
      await _show(tester, r.boot as Bootstrapper);

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('bootstrap-decision-templates')),
          matching: find.text('Accept'),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('bootstrap-install')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Installed, checksum verified'), findsOneWidget);
      expect((r.boot as Bootstrapper).installed.keys, ['templates']);
    },
  );

  testWidgets('a failed item shows its error and Retry installs it', (
    tester,
  ) async {
    final r = await tester.runAsync(bootstrapRig) as dynamic;
    r.server.put('templates', 'T1');
    r.server.failDownloads = {'https://x/templates'};
    await _show(tester, r.boot as Bootstrapper);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('bootstrap-decision-templates')),
        matching: find.text('Accept'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('bootstrap-install')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Failed: '), findsOneWidget);
    expect(find.textContaining('connection reset'), findsOneWidget);

    r.server.failDownloads = <String>{};
    await tester.tap(find.byKey(const Key('bootstrap-retry-templates')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Installed, checksum verified'), findsOneWidget);
  });

  testWidgets('Skip is remembered across a re-check', (tester) async {
    final r = await tester.runAsync(bootstrapRig) as dynamic;
    r.server.put('templates', 'T1');
    await _show(tester, r.boot as Bootstrapper);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('bootstrap-decision-templates')),
        matching: find.text('Skip'),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('bootstrap-refresh')));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();

    final seg = tester.widget<SegmentedButton<Decision>>(
      find.byKey(const Key('bootstrap-decision-templates')),
    );
    expect(seg.selected, {Decision.skip});
  });

  testWidgets('offline: says so and still shows the retry', (tester) async {
    final r = await tester.runAsync(bootstrapRig) as dynamic;
    r.server.unreachable = true;
    await _show(tester, r.boot as Bootstrapper);
    expect(find.byKey(const Key('bootstrap-offline')), findsOneWidget);
    expect(find.textContaining('Existing projects still open'), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-retry-check')), findsOneWidget);
  });

  testWidgets('an unsigned manifest offers nothing and says why', (
    tester,
  ) async {
    final r = await tester.runAsync(bootstrapRig) as dynamic;
    r.server.put('templates', 'T1');
    r.server.unsigned = true;
    await _show(tester, r.boot as Bootstrapper);
    expect(find.byKey(const Key('bootstrap-rejected')), findsOneWidget);
    expect(find.textContaining('not signed'), findsOneWidget);
    expect(find.byKey(const Key('bootstrap-item-templates')), findsNothing);
  });

  group('UpdateConfig', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('upd_cfg'));
    tearDown(() => dir.deleteSync(recursive: true));

    File prefs(String content) =>
        File('${dir.path}/studio_prefs.json')..writeAsStringSync(content);

    test('needs a URL and a 32-byte key; anything else is not configured', () {
      final good = base64Encode(List.filled(32, 7));
      expect(
        UpdateConfig.load(
          prefs(
            '{"updates":{"manifestUrl":"https://x/m.json","publicKey":"$good"}}',
          ),
        )!.manifestUrl,
        'https://x/m.json',
      );
      expect(
        UpdateConfig.load(
          prefs('{"updates":{"manifestUrl":"https://x/m.json"}}'),
        ),
        isNull,
      );
      expect(
        UpdateConfig.load(
          prefs(
            '{"updates":{"manifestUrl":"https://x","publicKey":"${base64Encode([1, 2, 3])}"}}',
          ),
        ),
        isNull,
      );
      expect(UpdateConfig.load(prefs('{"shortcuts":{}}')), isNull);
      expect(UpdateConfig.load(prefs('not json')), isNull);
      expect(UpdateConfig.load(File('${dir.path}/missing.json')), isNull);
    });
  });

  testWidgets(
    'the open screen explains how to configure updates when none are',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProjectOpenScreen(
            onOpened: (_, _) {},
            updateConfig: () => null,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open-updates')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('updates-not-configured')), findsOneWidget);
      expect(find.textContaining('publicKey'), findsOneWidget);
    },
  );

  testWidgets('with a config the open screen opens the updates window', (
    tester,
  ) async {
    final config = UpdateConfig('https://x/m.json', List.filled(32, 1));
    await tester.pumpWidget(
      MaterialApp(
        home: ProjectOpenScreen(
          onOpened: (_, _) {},
          updateConfig: () => config,
        ),
      ),
    );
    // The real config would build an HTTP bootstrapper; here we only check navigation happens.
    await tester.tap(find.byKey(const Key('open-updates')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Updates and downloads'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
