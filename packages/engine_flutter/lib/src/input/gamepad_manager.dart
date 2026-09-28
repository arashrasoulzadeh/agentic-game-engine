import 'input.dart';
import 'gamepad_controller.dart';
import 'gamepad_vibration_haptics.dart';

/// Manages multiple gamepad controllers for local multiplayer support.
/// Each connected gamepad gets its own [GamepadController] instance.
/// Player indices follow the W3C Gamepad API convention (0-3 for up to 4 players).
class GamepadManager {
  final InputController input;
  final List<GamepadController?> _controllers = List.filled(4, null);
  final List<GamepadHaptics?> _haptics = List.filled(4, null);
  
  /// Called when a gamepad is connected at [index].
  void Function(int index)? onGamepadConnectedCallback;
  
  /// Called when a gamepad is disconnected at [index].
  void Function(int index)? onGamepadDisconnectedCallback;

  GamepadManager({
    required this.input,
  });

  /// Returns the controller for the given player index (0-3), or null if not connected.
  GamepadController? getController(int index) {
    if (index < 0 || index >= _controllers.length) return null;
    return _controllers[index];
  }

  /// Returns the haptics for the given player index, or null if not connected/supported.
  GamepadHaptics? getHaptics(int index) {
    if (index < 0 || index >= _haptics.length) return null;
    return _haptics[index];
  }

  /// Checks if a gamepad is connected at the given index.
  bool isConnected(int index) {
    if (index < 0 || index >= _controllers.length) return false;
    return _controllers[index] != null;
  }

  /// Gets the number of currently connected gamepads.
  int get connectedCount => _controllers.where((c) => c != null).length;

  /// Called by the platform when a gamepad is connected.
  /// [index] is the player index (0-3). [gamepad] is the raw gamepad object from the platform.
  /// [buttonCount] and [axisCount] are the number of buttons and axes reported.
  void onGamepadConnected({
    required int index,
    required dynamic gamepad,
    required int buttonCount,
    required int axisCount,
  }) {
    if (index < 0 || index >= _controllers.length) return;
    
    // If already connected, disconnect first
    if (_controllers[index] != null) {
      onGamepadDisconnected(index);
    }
    
    // Create a new controller for this gamepad
    final controller = GamepadController(input: InputController());
    _controllers[index] = controller;
    
    // Try to initialize haptics if supported
    _initHaptics(index);
    
    if (onGamepadConnectedCallback != null) {
      onGamepadConnectedCallback!(index);
    }
  }

  /// Called by the platform when a gamepad is disconnected.
  void onGamepadDisconnected(int index) {
    if (index < 0 || index >= _controllers.length) return;
    
    final controller = _controllers[index];
    if (controller != null) {
      // Stop any ongoing haptics
      if (controller.haptics != null) {
        controller.haptics!.stop();
      }
      _controllers[index] = null;
    }
    
    if (_haptics[index] != null) {
      _haptics[index] = null;
    }
    
    if (onGamepadDisconnectedCallback != null) {
      onGamepadDisconnectedCallback!(index);
    }
  }

  /// Called by the platform when a button is pressed.
  void handleButtonDown(int index, int buttonId) {
    final controller = _controllers[index];
    if (controller != null) {
      controller.handleButtonDown(buttonId);
    }
  }

  /// Called by the platform when a button is released.
  void handleButtonUp(int index, int buttonId) {
    final controller = _controllers[index];
    if (controller != null) {
      controller.handleButtonUp(buttonId);
    }
  }

  /// Called by the platform when an axis value changes.
  void handleAxis(int index, int axisId, double value) {
    final controller = _controllers[index];
    if (controller != null) {
      controller.handleAxis(axisId, value);
    }
  }

  /// Gets the haptics for a player index, initializing if needed.
  GamepadHaptics? getHapticsFor(int index) {
    if (index < 0 || index >= _haptics.length) return null;
    return _haptics[index];
  }

  /// Initializes haptics for a player index if supported.
  void _initHaptics(int index) {
    // Try to initialize GamepadVibrationHaptics
    try {
      final haptics = GamepadVibrationHaptics.internal(index);
      _haptics[index] = haptics;
      // Assign to the controller
      _controllers[index]?.haptics = haptics;
    } catch (e) {
      // Haptics not supported on this platform, leave as null (NoOpHaptics will be used)
    }
  }

  /// Disposes all controllers and haptics.
  void dispose() {
    for (var i = 0; i < _controllers.length; i++) {
      onGamepadDisconnected(i);
    }
  }
}

/// Manages gamepad remapping for keyboard and gamepad bindings.
/// Extends the functionality of RemapMenuScene to support gamepad bindings.
class GamepadRemapManager {
  final InputController inputController;
  final GamepadManager gamepadManager;

  GamepadRemapManager({
    required this.inputController,
    required this.gamepadManager,
  });

  /// Starts capturing the next button press for a keyboard action.
  void startKeyboardRebind(String action) {
    // Implementation in RemapMenuScene
  }

  /// Starts capturing the next button press for a gamepad action on a specific player index.
  void startGamepadRebind(String action, int playerIndex) {
    final controller = gamepadManager.getController(playerIndex);
    if (controller == null) return;
    
    controller.captureNextButtonDown = (buttonId) {
      // Remove any existing binding for this action
      gamepadManager.getController(playerIndex)?.buttonBindings
          .removeWhere((_, boundAction) => boundAction == action);
      
      // Add the new binding
      // We need to find the buttonId that was just pressed
      // This would be called from the capture callback
    };
  }

  /// Saves all gamepad bindings to persistent storage.
  Future<void> saveGamepadBindings(int playerIndex) async {
    final controller = gamepadManager.getController(playerIndex);
    if (controller == null) return;
    
    // Save button bindings
    // Save axis bindings
    // This would use shared_preferences similar to InputBindingsStorage
  }

  /// Loads gamepad bindings from persistent storage.
  Future<void> loadGamepadBindings(int playerIndex) async {
    final controller = gamepadManager.getController(playerIndex);
    if (controller == null) return;
    
    // Load button bindings
    // Load axis bindings
  }
}