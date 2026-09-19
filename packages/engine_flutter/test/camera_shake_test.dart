import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Camera shake enhancements', () {
    test('Camera.shake with impulse applies single jolt', () {
      final camera = Camera();
      camera.shake(magnitude: 20, duration: 0.5, impulse: true);

      camera.update(0.016);
      final offset1 = camera.shakeOffset;
      expect(offset1.distance, greaterThan(0));

      camera.update(0.016);
      final offset2 = camera.shakeOffset;
      // Impulse should decay to near zero quickly
      expect(offset2.distance, lessThan(offset1.distance));
    });

    test('Camera.shake with sustained applies continuous shake', () {
      final camera = Camera();
      camera.shake(magnitude: 20, duration: 1.0, impulse: false);

      camera.update(0.016);
      final offset1 = camera.shakeOffset;
      expect(offset1.distance, greaterThan(0));

      camera.update(0.016);
      final offset2 = camera.shakeOffset;
      expect(offset2.distance, greaterThan(0));
      // Sustained should not decay to zero quickly
      expect(offset2.distance, closeTo(offset1.distance, offset1.distance * 0.5));
    });

    test('Camera.shake with per-axis control', () {
      final camera = Camera();
      camera.shake(magnitude: 20, duration: 0.5, impulse: true, axis: ShakeAxis.x);

      camera.update(0.016);
      final offset = camera.shakeOffset;
      expect(offset.dy, 0); // Y should not shake
      expect(offset.dx, not(0)); // X should shake
    });

    test('Camera.shake additive stacking', () {
      final camera = Camera();
      camera.shake(magnitude: 10, duration: 1.0);
      camera.shake(magnitude: 10, duration: 1.0);

      camera.update(0.016);
      final offset1 = camera.shakeOffset;

      camera.shake(magnitude: 10, duration: 1.0);
      camera.update(0.016);
      final offset2 = camera.shakeOffset;

      // Multiple shakes should add up
      expect(offset2.distance, greaterThan(offset1.distance));
    });

    test('Camera.shake frequency parameter', () {
      final camera = Camera();
      camera.shake(magnitude: 20, duration: 0.5, frequency: 10.0);

      final offsets = <double>[];
      for (int i = 0; i < 20; i++) {
        camera.update(0.016);
        offsets.add(camera.shakeOffset.distance);
      }

      // Higher frequency should produce more oscillations
      int signChanges = 0;
      for (int i = 1; i < offsets.length; i++) {
        if ((offsets[i] - offsets[i-1]).sign != (offsets[i-1] - (i >= 2 ? offsets[i-2] : 0)).sign) {
          signChanges++;
        }
      }
      expect(signChanges, greaterThan(5));
    });

    test('Camera.shake decay parameter', () {
      final camera = Camera();
      camera.shake(magnitude: 20, duration: 1.0, decay: 0.5);

      camera.update(0.016);
      final offset1 = camera.shakeOffset.distance;

      for (int i = 0; i < 20; i++) {
        camera.update(0.016);
      }
      final offset2 = camera.shakeOffset.distance;

      // With decay, should decay faster than without
      expect(offset2, lessThan(offset1 * 0.1));
    });

    test('Camera.shake decay parameter sustained', () {
      final camera = Camera();
      camera.shake(magnitude: 20, duration: 1.0, decay: 0.5, impulse: false);

      camera.update(0.016);
      final offset1 = camera.shakeOffset.distance;

      for (int i = 0; i < 10; i++) {
        camera.update(0.016);
      }
      final offset2 = camera.shakeOffset.distance;

      // Even sustained should decay with decay parameter
      expect(offset2, lessThan(offset1));
    });
  });
}