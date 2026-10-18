import 'dart:io';

import 'package:engine_studio/src/prefs/shortcuts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => ShortcutMap.current = ShortcutMap());

  group('parseBinding', () {
    test(
      'mod means Command and Control, so one default works on every platform',
      () {
        final a = parseBinding('mod+shift+f');
        expect(a.length, 2);
        expect(a.map((x) => (x.meta, x.control)).toSet(), {
          (true, false),
          (false, true),
        });
        expect(
          a.every((x) => x.shift && x.trigger == LogicalKeyboardKey.keyF),
          isTrue,
        );
      },
    );

    test('ctrl pins a single modifier; digits work', () {
      final a = parseBinding('ctrl+alt+3');
      expect(a.single.control, isTrue);
      expect(a.single.alt, isTrue);
      expect(a.single.trigger, LogicalKeyboardKey.digit3);
    });

    test('anything malformed yields no binding rather than throwing', () {
      for (final bad in ['', 'f', 'mod+', 'hyper+f', 'mod+nope', 'shift+f']) {
        expect(parseBinding(bad), isEmpty, reason: bad);
      }
    });
  });

  group('ShortcutMap', () {
    test('defaults, then overrides', () {
      final map = ShortcutMap({StudioAction.save: 'mod+k'});
      expect(map.bindingFor(StudioAction.save), 'mod+k');
      expect(map.bindingFor(StudioAction.find), 'mod+f');
      expect(
        map.activatorsFor(StudioAction.save).first.trigger,
        LogicalKeyboardKey.keyK,
      );
    });

    test('defaults do not conflict; a duplicate binding is reported', () {
      expect(ShortcutMap().conflicts(), isEmpty);
      final clash = ShortcutMap({StudioAction.replace: 'mod+f'});
      expect(clash.conflicts(), [(StudioAction.find, StudioAction.replace)]);
    });

    test('shift distinguishes bindings on the same key', () {
      expect(
        ShortcutMap({StudioAction.replace: 'mod+shift+f'}).conflicts().length,
        1,
      );
      expect(ShortcutMap({StudioAction.replace: 'mod+g'}).conflicts(), isEmpty);
    });

    test(
      'a file round-trips; a missing, broken or foreign file gives defaults',
      () {
        final dir = Directory.systemTemp.createTempSync('prefs');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/sub/studio_prefs.json');
        expect(loadShortcuts(file).bindingFor(StudioAction.save), 'mod+s');

        saveShortcuts(file, ShortcutMap({StudioAction.save: 'mod+k'}));
        expect(loadShortcuts(file).bindingFor(StudioAction.save), 'mod+k');

        file.writeAsStringSync('{ not json');
        expect(loadShortcuts(file).bindingFor(StudioAction.save), 'mod+s');
        file.writeAsStringSync('{"shortcuts":{"save":"mod+k","fly":"mod+x"}}');
        expect(loadShortcuts(file).bindingFor(StudioAction.save), 'mod+k');
      },
    );

    test('the prefs file lives under the home folder, not a project', () {
      expect(
        studioPrefsFile(env: {'HOME': '/h'}).path,
        '/h/.game_agent/studio_prefs.json',
      );
    });
  });

  testWidgets('the bindings fire the handler for the configured keys only', (
    tester,
  ) async {
    var saves = 0;
    final map = ShortcutMap({StudioAction.save: 'ctrl+k'});
    await tester.pumpWidget(
      MaterialApp(
        home: CallbackShortcuts(
          bindings: map.bindings({StudioAction.save: () => saves++}),
          child: const Focus(autofocus: true, child: SizedBox()),
        ),
      ),
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    expect(saves, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    expect(saves, 1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });
}
