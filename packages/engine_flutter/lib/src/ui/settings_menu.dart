import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';

/// A widget spec for settings menus — extends the button/menu concept
/// to cover common settings UI patterns: toggles, sliders, dropdowns,
/// and scrollable lists. All specs are plain data; the engine handles
/// spawning entities, hit-testing, and rendering.
abstract class SettingsWidgetSpec {
  /// Unique identifier for this widget — used as actionId in hit-testing.
  final String id;

  /// Human-readable label shown next to or above the widget.
  final String label;

  /// Optional tooltip/help text shown on long-press or hover.
  final String? tooltip;

  const SettingsWidgetSpec({
    required this.id,
    required this.label,
    this.tooltip,
  });
}

/// A toggle switch (on/off) bound to a boolean PlayerOptions key.
class SettingsToggleSpec extends SettingsWidgetSpec {
  /// The key in PlayerOptions.custom (or a known option) to bind to.
  final String optionKey;

  /// When true, shows as a switch; when false, shows as a checkbox.
  final bool useSwitchStyle;

  /// Custom "on" and "off" labels (defaults to "ON"/"OFF").
  final String onLabel;
  final String offLabel;

  const SettingsToggleSpec({
    required super.id,
    required super.label,
    required this.optionKey,
    this.useSwitchStyle = true,
    this.onLabel = 'ON',
    this.offLabel = 'OFF',
    super.tooltip,
  });
}

/// A slider bound to a numeric PlayerOptions key (double or int).
class SettingsSliderSpec extends SettingsWidgetSpec {
  /// The key in PlayerOptions.custom (or a known option) to bind to.
  final String optionKey;

  /// Minimum value.
  final double min;

  /// Maximum value.
  final double max;

  /// Number of discrete steps (null = continuous). If set, value snaps.
  final int? steps;

  /// Format string for the displayed value (e.g., "%.0f%%", "%.1f").
  final String valueFormat;

  /// Whether to show the current value next to the slider.
  final bool showValue;

  const SettingsSliderSpec({
    required super.id,
    required super.label,
    required this.optionKey,
    required this.min,
    required this.max,
    this.steps,
    this.valueFormat = '%.1f',
    this.showValue = true,
    super.tooltip,
  });
}

/// A dropdown/select menu bound to a PlayerOptions key with string values.
class SettingsDropdownSpec extends SettingsWidgetSpec {
  /// The key in PlayerOptions.custom (or a known option) to bind to.
  final String optionKey;

  /// Available options as a map of value -> display label.
  /// Order of iteration determines dropdown order.
  final Map<String, String> options;

  /// Placeholder text when no option is selected (null = first option).
  final String? placeholder;

  const SettingsDropdownSpec({
    required super.id,
    required super.label,
    required this.optionKey,
    required this.options,
    this.placeholder,
    super.tooltip,
  });
}

/// A section header/divider for grouping settings.
class SettingsSectionSpec extends SettingsWidgetSpec {
  const SettingsSectionSpec({
    required super.id,
    required super.label,
    super.tooltip,
  });
}

/// A scrollable list of options (for many items that don't fit on screen).
class SettingsListSpec extends SettingsWidgetSpec {
  /// Items in the list as a map of value -> display label.
  final Map<String, String> items;

  /// The key in PlayerOptions.custom to store the selected item's key.
  final String optionKey;

  /// Maximum number of visible items before scrolling (default 5).
  final int maxVisibleItems;

  const SettingsListSpec({
    required super.id,
    required super.label,
    required this.items,
    required this.optionKey,
    this.maxVisibleItems = 5,
    super.tooltip,
  });
}

/// A key binding editor for remapping keyboard/touch controls.
/// Allows the user to press a key to rebind an action.
class SettingsKeyBindingSpec extends SettingsWidgetSpec {
  /// The action ID to rebind (e.g., 'jump', 'move_left', 'attack').
  final String actionId;

  /// The input type this binding applies to.
  final InputType inputType;

  /// Current bound key/button display name (updated when user presses a key).
  String? currentBindingLabel;

  SettingsKeyBindingSpec({
    required super.id,
    required super.label,
    required this.actionId,
    this.inputType = InputType.keyboard,
    this.currentBindingLabel,
    super.tooltip,
  });

  /// Updates the display label for the current binding.
  void updateBindingLabel(String label) {
    currentBindingLabel = label;
  }
}

/// The type of input device for key bindings.
enum InputType {
  keyboard,
  gamepad,
  touch,
}

/// Base class for settings menus that automatically binds widgets to PlayerOptions.
/// Subclass and override [widgets] to define the settings UI.
abstract class SettingsMenuScene extends ButtonMenuScene {
  /// The PlayerOptionsManager to bind widgets to.
  /// Must be set before [populate] is called.
  late final PlayerOptionsManager optionsManager;

  /// The list of settings widgets to display, in order.
  List<SettingsWidgetSpec> get widgets;

  /// Optional title shown at the top of the settings menu.
  String? get title => null;

  /// Called when any widget value changes.
  /// Override to apply changes immediately (e.g., update audio volume).
  void onValueChanged(String key, dynamic value) {}

  @override
  List<MenuButtonSpec> buttons() {
    final specs = <MenuButtonSpec>[];

    if (title != null) {
      specs.add(MenuButtonSpec(
        label: title!,
        actionId: '__title__',
        labelFontSize: 28,
        labelColorArgb: 0xFFFFFF00,
      ));
    }

    for (final widget in widgets) {
      specs.add(_widgetToButtonSpec(widget));
    }

    // Always add a "Back" button at the bottom
    specs.add(MenuButtonSpec(
      label: 'Back',
      actionId: '__back__',
      labelFontSize: 20,
    ));

    return specs;
  }

  MenuButtonSpec _widgetToButtonSpec(SettingsWidgetSpec widget) {
    final currentValue = optionsManager.getOption(widget.id);
    String displayLabel = widget.label;

    if (widget is SettingsToggleSpec) {
      final isOn = currentValue == true;
      displayLabel = '${widget.label}: ${isOn ? widget.onLabel : widget.offLabel}';
    } else if (widget is SettingsSliderSpec) {
      final value = (currentValue as num?)?.toDouble() ?? widget.min;
      displayLabel =
          '${widget.label}: ${widget.valueFormat.replaceFirst(RegExp(r'%.[df]'), value.toStringAsFixed(1))}';
    } else if (widget is SettingsDropdownSpec) {
      final selected = currentValue as String?;
      final label = selected != null && widget.options.containsKey(selected)
          ? widget.options[selected]!
          : widget.placeholder ?? 'Select...';
      displayLabel = '${widget.label}: $label';
    } else if (widget is SettingsListSpec) {
      final selected = currentValue as String?;
      final label = selected != null && widget.items.containsKey(selected)
          ? widget.items[selected]!
          : 'Select...';
      displayLabel = '${widget.label}: $label';
    } else if (widget is SettingsKeyBindingSpec) {
      final label = widget.currentBindingLabel ?? 'Press to bind...';
      displayLabel = '${widget.label}: $label';
    }

    return MenuButtonSpec(
      label: displayLabel,
      actionId: widget.id,
      labelFontSize: 18,
      labelColorArgb: 0xFFFFFFFF,
    );
  }

  @override
  void onButtonPressed(String actionId, SceneController scenes) {
    if (actionId == '__title__') return;
    if (actionId == '__back__') {
      scenes.popOverlay();
      return;
    }

    final widget = widgets.firstWhere((w) => w.id == actionId);
    _handleWidgetAction(widget, scenes);
  }

  void _handleWidgetAction(SettingsWidgetSpec widget, SceneController scenes) {
    if (widget is SettingsToggleSpec) {
      final current = optionsManager.getOption(widget.id) == true;
      optionsManager.setOption(widget.optionKey, !current);
      onValueChanged(widget.optionKey, !current);
    } else if (widget is SettingsSliderSpec) {
      // For slider, we'd need a more complex interaction (drag)
      // For now, cycle through steps or min/max
      final current = (optionsManager.getOption(widget.optionKey) as num?)?.toDouble() ?? widget.min;
      double nextValue;
      if (widget.steps != null) {
        final stepSize = (widget.max - widget.min) / widget.steps!;
        nextValue = (current + stepSize).clamp(widget.min, widget.max);
        if (nextValue > widget.max) nextValue = widget.min;
      } else {
        nextValue = (current + (widget.max - widget.min) * 0.1).clamp(widget.min, widget.max);
      }
      optionsManager.setOption(widget.optionKey, nextValue);
      onValueChanged(widget.optionKey, nextValue);
    } else if (widget is SettingsDropdownSpec) {
      final keys = widget.options.keys.toList();
      final current = optionsManager.getOption(widget.optionKey) as String?;
      final currentIndex = current != null ? keys.indexOf(current) : -1;
      final nextIndex = (currentIndex + 1) % keys.length;
      optionsManager.setOption(widget.optionKey, keys[nextIndex]);
      onValueChanged(widget.optionKey, keys[nextIndex]);
    } else if (widget is SettingsListSpec) {
      final keys = widget.items.keys.toList();
      final current = optionsManager.getOption(widget.optionKey) as String?;
      final currentIndex = current != null ? keys.indexOf(current) : -1;
      final nextIndex = (currentIndex + 1) % keys.length;
      optionsManager.setOption(widget.optionKey, keys[nextIndex]);
      onValueChanged(widget.optionKey, keys[nextIndex]);
    } else if (widget is SettingsKeyBindingSpec) {
      // For key binding, we'd need a more complex interaction
      // For now, just show a message that the user should press a key
      // In a full implementation, you'd capture the next key press
      onValueChanged(widget.actionId, 'waiting_for_input');
    }
  }
}

/// Extension to add settings menu helpers to any SceneController.
extension SettingsMenuExtension on SceneController {
  /// Pushes a settings menu overlay.
  void pushSettingsMenu(SettingsMenuScene menu) {
    pushOverlay(menu);
  }
}

/// A ready-to-use settings menu with all standard options including accessibility.
class AccessibilitySettingsMenu extends SettingsMenuScene {
  @override
  String? get title => 'Accessibility Settings';

  @override
  List<SettingsWidgetSpec> get widgets => [
    SettingsSectionSpec(id: 'visual', label: 'Visual'),
    SettingsToggleSpec(
      id: 'highContrast',
      label: 'High Contrast Mode',
      optionKey: 'highContrast',
      onLabel: 'ON',
      offLabel: 'OFF',
      tooltip: 'Increases contrast for better visibility',
    ),
    SettingsDropdownSpec(
      id: 'colorblindMode',
      label: 'Colorblind Mode',
      optionKey: 'colorblindMode',
      options: {
        'none': 'None',
        'protanopia': 'Protanopia (Red-blind)',
        'deuteranopia': 'Deuteranopia (Green-blind)',
        'tritanopia': 'Tritanopia (Blue-blind)',
      },
      placeholder: 'Select colorblind mode',
      tooltip: 'Simulates color vision deficiencies',
    ),
    SettingsToggleSpec(
      id: 'reduceMotion',
      label: 'Reduce Motion',
      optionKey: 'reduceMotion',
      tooltip: 'Reduces animations and motion effects',
    ),
    SettingsSliderSpec(
      id: 'textScale',
      label: 'Text Size',
      optionKey: 'textScale',
      min: 0.5,
      max: 3.0,
      steps: 10,
      valueFormat: '%.1fx',
      tooltip: 'Scales all UI text',
    ),
    SettingsSliderSpec(
      id: 'screenShake',
      label: 'Screen Shake Intensity',
      optionKey: 'screenShakeIntensity',
      min: 0.0,
      max: 1.0,
      steps: 10,
      valueFormat: '%.0f%%',
      tooltip: 'Reduces screen shake effects',
    ),

    SettingsSectionSpec(id: 'audio', label: 'Audio'),
    SettingsSliderSpec(
      id: 'masterVolume',
      label: 'Master Volume',
      optionKey: 'masterVolume',
      min: 0.0,
      max: 1.0,
      steps: 20,
      valueFormat: '%.0f%%',
    ),
    SettingsSliderSpec(
      id: 'musicVolume',
      label: 'Music Volume',
      optionKey: 'musicVolume',
      min: 0.0,
      max: 1.0,
      steps: 20,
      valueFormat: '%.0f%%',
    ),
    SettingsSliderSpec(
      id: 'sfxVolume',
      label: 'SFX Volume',
      optionKey: 'sfxVolume',
      min: 0.0,
      max: 1.0,
      steps: 20,
      valueFormat: '%.0f%%',
    ),

    SettingsSectionSpec(id: 'controls', label: 'Controls'),
    SettingsDropdownSpec(
      id: 'controlScheme',
      label: 'Control Scheme',
      optionKey: 'controlScheme',
      options: {
        'keyboard': 'Keyboard',
        'gamepad': 'Gamepad',
        'touch': 'Touch',
      },
    ),
    SettingsKeyBindingSpec(
      id: 'bindJump',
      label: 'Jump',
      actionId: 'jump',
      inputType: InputType.keyboard,
    ),
    SettingsKeyBindingSpec(
      id: 'bindMoveLeft',
      label: 'Move Left',
      actionId: 'move_left',
      inputType: InputType.keyboard,
    ),
    SettingsKeyBindingSpec(
      id: 'bindMoveRight',
      label: 'Move Right',
      actionId: 'move_right',
      inputType: InputType.keyboard,
    ),
    SettingsKeyBindingSpec(
      id: 'bindAttack',
      label: 'Attack',
      actionId: 'attack',
      inputType: InputType.keyboard,
    ),

    SettingsSectionSpec(id: 'gameplay', label: 'Gameplay'),
    SettingsSliderSpec(
      id: 'dialogueSpeed',
      label: 'Dialogue Speed',
      optionKey: 'dialogueSpeed',
      min: 0.5,
      max: 3.0,
      steps: 10,
      valueFormat: '%.1fx',
    ),
    SettingsDropdownSpec(
      id: 'locale',
      label: 'Language',
      optionKey: 'locale',
      options: {
        'en': 'English',
        'es': 'Español',
        'ja': '日本語',
        'fr': 'Français',
        'de': 'Deutsch',
      },
    ),
  ];

  @override
  void onValueChanged(String key, dynamic value) {
    switch (key) {
      case 'masterVolume':
      case 'musicVolume':
      case 'sfxVolume':
        // Apply audio changes immediately
        break;
      case 'textScale':
        // Text scaling is applied automatically by the renderer
        break;
      case 'colorblindMode':
        // Colorblind simulation would be applied by the renderer
        break;
      case 'highContrast':
        // High contrast mode would be applied by the renderer
        break;
    }
  }
}