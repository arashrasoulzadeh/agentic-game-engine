import 'dart:math';

import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Camera shake enhancements', () {
    // Camera.shake's per-frame jitter is `magnitude * (random * 2 - 1)` —
    // comparing two independent draws (e.g. "did it get smaller?") is
    // flaky with an unseeded Random, since the draw itself varies even
    // when the underlying envelope shrinks. Seeding makes every run of
    // these tests deterministic.
    test('Camera.shake with impulse decays to (near) zero by duration end', () {
      final camera = Camera(random: Random(1));
      camera.shake(magnitude: 20, duration: 0.5, impulse: true);

      camera.update(0.016);
      expect(camera.shakeOffset.distance, greaterThan(0));

      // 98% of the way through: falloff is t^2 with t = 0.01, so the
      // envelope (and therefore the bound on the jitter draw, whatever it
      // is) is magnitude * 0.0001 — tiny regardless of the random draw.
      camera.update(0.49);
      expect(camera.shakeOffset.distance, lessThan(0.1));

      // Past the full duration: no active shake left to jitter at all.
      camera.update(0.1);
      expect(camera.shakeOffset, Offset.zero);
    });

    test('Camera.shake sustained decays slower than impulse over the same span', () {
      // Same seed and update sequence on both, so they draw identical
      // underlying jitter fractions — any difference in the resulting
      // offset is purely down to impulse's quadratic vs. sustained's
      // linear (decay: 1.0, the default) falloff curve.
      final impulse = Camera(random: Random(1));
      impulse.shake(magnitude: 20, duration: 1.0, impulse: true);

      final sustained = Camera(random: Random(1));
      sustained.shake(magnitude: 20, duration: 1.0, impulse: false);

      for (int i = 0; i < 30; i++) {
        impulse.update(0.016);
        sustained.update(0.016);
      }

      expect(sustained.shakeOffset.distance, greaterThan(impulse.shakeOffset.distance));
    });

    test('Camera.shake with per-axis control', () {
      final camera = Camera(random: Random(1));
      camera.shake(magnitude: 20, duration: 0.5, impulse: true, axis: ShakeAxis.x);

      camera.update(0.016);
      final offset = camera.shakeOffset;
      expect(offset.dy, 0); // Y should not shake
      expect(offset.dx, isNot(0)); // X should shake
    });

    test('Camera.shake additive stacking', () {
      final camera = Camera(random: Random(1));
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
      final camera = Camera(random: Random(1));
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

    test('Camera.shake decay > 1 decays faster than linear (decay: 1.0)', () {
      // Per Camera.shake's own doc comment: "decay curve exponent (1.0 =
      // linear, >1 = faster decay, <1 = slower)" — falloff is
      // pow(remaining/duration, decay), and raising a fraction in (0, 1)
      // to a larger exponent makes it *smaller*, i.e. decays faster.
      final linear = Camera(random: Random(1));
      linear.shake(magnitude: 20, duration: 1.0, decay: 1.0);

      final fast = Camera(random: Random(1));
      fast.shake(magnitude: 20, duration: 1.0, decay: 3.0);

      for (int i = 0; i < 10; i++) {
        linear.update(0.016);
        fast.update(0.016);
      }

      expect(fast.shakeOffset.distance, lessThan(linear.shakeOffset.distance));
    });

    test('Camera.shake decay < 1 decays slower than linear (decay: 1.0)', () {
      final linear = Camera(random: Random(1));
      linear.shake(magnitude: 20, duration: 1.0, decay: 1.0, impulse: false);

      final slow = Camera(random: Random(1));
      slow.shake(magnitude: 20, duration: 1.0, decay: 0.3, impulse: false);

      for (int i = 0; i < 10; i++) {
        linear.update(0.016);
        slow.update(0.016);
      }

      expect(slow.shakeOffset.distance, greaterThan(linear.shakeOffset.distance));
    });
  });
}