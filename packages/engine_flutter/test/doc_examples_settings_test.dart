// The camera sample in docs/concepts/settings.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'binding the screen-shake setting to the camera silences or softens shake',
    () async {
      final options = PlayerOptionsManager(InMemoryPlayerOptionsStorage());
      final camera = Camera(zoom: 1);
      options.addListener(
        (o) => camera.shakeIntensity = o.screenShakeIntensity,
      );

      await options.setOption('screenShakeIntensity', 0.0);
      expect(camera.shakeIntensity, 0.0);
      camera.shake(magnitude: 20, duration: 0.3);
      camera.update(0.05);
      expect(
        camera.shakeOffset.distance,
        0,
        reason: 'the player turned shake off',
      );

      await options.setOption('screenShakeIntensity', 1.0);
      expect(camera.shakeIntensity, 1.0);
    },
  );
}
