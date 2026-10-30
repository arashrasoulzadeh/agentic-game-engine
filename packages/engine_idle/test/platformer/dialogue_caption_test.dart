import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart' as eng;
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late World world;
  late DialogueCaption caption;
  const text = 'راهزنان بر کاروان‌ها دستبرد می‌زدند'; // 35 chars

  setUp(() {
    world = World(width: 180, height: 320);
    registerCoreComponents(world);
    eng.registerFlutterComponents(world);
    caption = DialogueCaption.spawn(
      world,
      style: const HudTextStyle(x: 90, y: 160, fontSize: 7.5, rtl: true),
    );
  });

  String onScreen() {
    final texts = world.storeOf<eng.Text>();
    return texts.denseAt(0).text;
  }

  test('sits where its style says, right-to-left', () {
    final p = world.storeOf<Position>().denseAt(0);
    expect((p.x, p.y), (90, 160));
    expect(world.storeOf<eng.Text>().denseAt(0).rtl, isTrue);
    expect(world.storeOf<eng.Text>().denseAt(0).fontSize, 7.5);
    expect(world.storeOf<eng.Text>().denseAt(0).screenSpace, isFalse);
  });

  test('types in through the dialogue runner, character by character', () {
    caption.show(world, text);
    expect(onScreen(), '');
    var last = 0;
    var steps = 0;
    while (onScreen() != text && steps++ < 200) {
      caption.update(world, 0.05);
      expect(onScreen().length, greaterThanOrEqualTo(last));
      expect(text.startsWith(onScreen()), isTrue);
      last = onScreen().length;
    }
    expect(onScreen(), text);
    // 35 characters at 40 per second take about 0.9 s
    expect(
      steps * 0.05,
      closeTo(text.length / DialogueCaption.typeCharsPerSecond, 0.1),
    );
  });

  test('holds the full line until hidden, then erases backwards faster', () {
    caption.show(world, text);
    for (var i = 0; i < 40; i++) {
      caption.update(world, 0.05);
    }
    expect(onScreen(), text);
    for (var i = 0; i < 10; i++) {
      caption.update(world, 0.05); // still holding
    }
    expect(onScreen(), text);

    caption.hide();
    var steps = 0;
    var last = text.length + 1;
    while (caption.visible && steps++ < 200) {
      caption.update(world, 0.05);
      expect(onScreen().length, lessThan(last));
      last = onScreen().length;
    }
    expect(caption.visible, isFalse);
    expect(onScreen(), '');
    // erasing is `eraseSpeedUp` times faster than typing
    expect(
      steps * 0.05,
      lessThan(text.length / DialogueCaption.typeCharsPerSecond / 2),
    );
  });

  test('showing a new line replaces the old; empty text clears', () {
    caption.show(world, text);
    caption.update(world, 0.3);
    expect(onScreen(), isNotEmpty);
    caption.show(world, 'abc');
    expect(onScreen(), '');
    for (var i = 0; i < 10; i++) {
      caption.update(world, 0.05);
    }
    expect(onScreen(), 'abc');
    caption.show(world, '');
    expect(caption.visible, isFalse);
    expect(onScreen(), '');
  });
}
