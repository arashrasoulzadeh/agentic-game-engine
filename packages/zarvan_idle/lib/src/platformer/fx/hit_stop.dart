import 'dart:math' as math;

import 'package:zarvan_core/zarvan_core.dart';

/// Freezes combat and animation for a moment. [freeze] pauses the named
/// systems; [update] (call it with the real frame time) resumes them.
class HitStop {
  HitStop(
    this.world, {
    this.systems = const ['autoCombat', 'animation', 'spriteState', 'movement'],
  });

  final World world;
  final List<String> systems;
  double _remaining = 0;

  bool get frozen => _remaining > 0;

  void freeze(double seconds) {
    if (seconds <= 0) return;
    if (!frozen) _set(false);
    _remaining = math.max(_remaining, seconds);
  }

  void update(double realDt) {
    if (!frozen) return;
    _remaining -= realDt;
    if (_remaining <= 0) {
      _remaining = 0;
      _set(true);
    }
  }

  void _set(bool enabled) {
    for (final name in systems) {
      if (world.systemOrder.contains(name)) {
        world.setSystemEnabled(name, enabled);
      }
    }
  }
}
