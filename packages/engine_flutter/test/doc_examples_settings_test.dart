// The camera sample in docs/concepts/settings.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a game applies the player\'s screen-shake setting itself', () async {
    final options = PlayerOptionsManager(InMemoryPlayerOptionsStorage());
    await options.setOption('screenShakeIntensity', 0.25);

    final camera = Camera(zoom: 1);
    // The engine does not read PlayerOptions: scaling the effect is the game's job.
    camera.shake(magnitude: 20 * options.options.screenShakeIntensity, duration: 0.3);

    expect(options.options.screenShakeIntensity, 0.25);
  });
}
