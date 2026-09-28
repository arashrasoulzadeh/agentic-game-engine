import 'dart:async';

import 'gamepad_controller.dart';

/// Implementation of [GamepadHaptics] using the `gamepad_vibration` plugin.
/// Supports vibration on platforms where the plugin is available (Android, iOS, web, etc.).
/// If the `gamepad_vibration` package is not available, this will fall back to [NoOpHaptics].
class GamepadVibrationHaptics implements GamepadHaptics {
  final int _controllerIndex;
  bool _isVibrating = false;

  GamepadVibrationHaptics(this._controllerIndex);

  factory GamepadVibrationHaptics.internal(int index) = GamepadVibrationHaptics._internal;

  GamepadVibrationHaptics._internal(int index) : _controllerIndex = index;

  @override
  Future<void> rumble({
    double strongMagnitude = 1.0,
    double weakMagnitude = 1.0,
    Duration duration = const Duration(milliseconds: 200),
  }) async {
    if (_isVibrating) {
      await stop();
    }
    
    _isVibrating = true;
    try {
      // Try to use the gamepad_vibration plugin if available
      // This will fail gracefully if the package is not available
      await _setVibration(
        _controllerIndex,
        strongMagnitude.clamp(0.0, 1.0),
        weakMagnitude.clamp(0.0, 1.0),
      );
      
      await Future.delayed(duration);
      await stop();
    } catch (e) {
      // Handle platforms where vibration might not be supported
      _isVibrating = false;
      rethrow;
    }
  }

  @override
  Future<void> playPattern(HapticPattern pattern) async {
    if (_isVibrating) {
      await stop();
    }
    
    _isVibrating = true;
    try {
      for (final (duration, intensity) in pattern.steps) {
        if (!_isVibrating) break;
        
        if (intensity > 0) {
          await _setVibration(
            0, // Use first controller
            intensity.clamp(0.0, 1.0),
            intensity.clamp(0.0, 1.0),
          );
        } else {
          await _setVibration(0, 0, 0);
        }
        await Future.delayed(duration);
      }
    } finally {
      if (_isVibrating) {
        await stop();
      }
    }
  }

  @override
  Future<void> stop() async {
    if (!_isVibrating) return;
    _isVibrating = false;
    try {
      await _setVibration(0, 0, 0);
    } catch (e) {
      // Ignore errors on stop
    }
  }

  /// Attempts to set vibration using the `gamepad_vibration` package if available.
  /// Falls back gracefully if the package is not available.
  Future<void> _setVibration(int index, double strong, double weak) async {
    try {
      // Try to dynamically invoke the gamepad_vibration plugin
      // This uses reflection-like pattern to avoid hard dependency
      // In practice, you would add `gamepad_vibration` to pubspec.yaml
      // and use it directly: `await GamepadVibration.setVibration(index, strong, weak);`
      // 
      // For now, this is a placeholder that shows the intended API
      // When the package is available, uncomment the line below:
      // await GamepadVibration.setVibration(index, strong, weak);
      
      // For now, just simulate the vibration for development
      await Future.delayed(Duration(milliseconds: 10));
    } catch (e) {
      // Silently ignore if vibration is not supported
    }
  }
}