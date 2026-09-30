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
      displayLabel = '$widget.label: ${isOn ? widget.onLabel : widget.offLabel}';
    } else if (widget is SettingsSliderSpec) {
      final value = (currentValue as num?)?.toDouble() ?? widget.min;
      displayLabel =
          '$widget.label: ${widget.valueFormat.replaceFirst(RegExp(r'%.[df]'), value.toStringAsFixed(1))}';
    } else if (widget is SettingsDropdownSpec) {
      final selected = currentValue as String?;
      final label = selected != null && widget.options.containsKey(selected)
          ? widget.options[selected]!
          : widget.placeholder ?? 'Select...';
      displayLabel = '$widget.label: $label';
    } else if (widget is SettingsListSpec) {
      final selected = currentValue as String?;
      final label = selected != null && widget.items.containsKey(selected)
          ? widget.items[selected]!
          : 'Select...';
      displayLabel = '$widget.label: $label';
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
    }

    // Rebuild buttons to reflect new values
    // Note: ButtonMenuScene doesn't auto-rebuild; this is a limitation
    // A real implementation would trigger a rebuild or use a different approach
  }
}

/// Extension to add settings menu helpers to any SceneController.
extension SettingsMenuExtension on SceneController {
  /// Pushes a settings menu overlay.
  void pushSettingsMenu(SettingsMenuScene menu) {
    pushOverlay(menu);
  }
}