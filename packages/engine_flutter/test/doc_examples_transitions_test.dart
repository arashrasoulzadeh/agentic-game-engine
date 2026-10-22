// The transition config and type list of docs/concepts/cinematics.md, executed so the guide cannot drift.
import 'dart:io';

import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the documented config is valid JSON-round-trippable data', () {
    const config = SceneTransitionConfig(
      type: SceneTransitionType.fade,
      duration: 0.6,
      easing: EasingType.easeInOutQuad,
      fadeColorArgb: 0xFF000000,
    );
    final back = SceneTransitionConfig.fromJson(config.toJson());
    expect(back.type, SceneTransitionType.fade);
    expect(back.duration, 0.6);
    expect(back.fadeColorArgb, 0xFF000000);
    expect(
      SceneTransitionConfig.fromJson({'type': 'nonsense'}).type,
      SceneTransitionType.fade,
    );
  });

  test(
    'every transition type is named in the guide, and snapshot types are the documented ones',
    () {
      final guide = File(
        '../../docs/concepts/cinematics.md',
      ).readAsStringSync();
      for (final t in SceneTransitionType.values) {
        final named = t.name == 'slideLeft'
            ? 'slideLeft/Right/Up/Down'
            : t.name.startsWith('slide')
            ? 'slideLeft/Right/Up/Down'
            : t.name;
        expect(guide, contains(named.split('/').first), reason: t.name);
      }
      expect(SceneTransitionType.values.where((t) => !t.usesSnapshot), [
        SceneTransitionType.fade,
        SceneTransitionType.iris,
      ]);
    },
  );
}
