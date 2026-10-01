import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestSettingsMenu extends SettingsMenuScene {
  @override
  List<SettingsWidgetSpec> get widgets => [
        const SettingsToggleSpec(id: 'sfx', label: 'Sound Effects', optionKey: 'sfxOn'),
        const SettingsSliderSpec(
          id: 'vol', label: 'Volume', optionKey: 'volume', min: 0, max: 1),
        const SettingsDropdownSpec(
          id: 'quality',
          label: 'Quality',
          optionKey: 'quality',
          options: {'low': 'Low', 'high': 'High'},
        ),
        const SettingsListSpec(
          id: 'region',
          label: 'Region',
          optionKey: 'region',
          items: {'us': 'United States', 'eu': 'Europe'},
        ),
        SettingsKeyBindingSpec(id: 'jump', label: 'Jump', actionId: 'jump'),
      ];
}

void main() {
  group('SettingsMenuScene.buttons', () {
    late _TestSettingsMenu scene;

    setUp(() {
      scene = _TestSettingsMenu()
        ..optionsManager = PlayerOptionsManager(InMemoryPlayerOptionsStorage());
    });

    // Regression test: _widgetToButtonSpec used `'$widget.label: ...'`
    // (interpolating `widget`'s own toString(), then appending the
    // literal text ".label: ...") instead of `'${widget.label}: ...'`
    // for every spec type -- every settings row showed
    // "Instance of 'SettingsToggleSpec'.label: ON" instead of the
    // actual label. Also, the SettingsListSpec branch had an
    // accidentally duplicated `else if (widget is SettingsListSpec)`
    // where the first (always-taken, since it's first) copy did
    // nothing but declare an unused local, silently making every
    // SettingsListSpec row fall through to the bare `widget.label`
    // default instead of showing the selected item.
    test('every widget type shows its real label, not toString() debris', () {
      final labels = scene.buttons().map((b) => b.label).toList();
      for (final label in labels) {
        expect(label, isNot(contains('Instance of')));
      }
    });

    test('SettingsToggleSpec shows label and on/off state', () {
      final label = scene.buttons().firstWhere((b) => b.actionId == 'sfx').label;
      expect(label, 'Sound Effects: OFF');
    });

    test('SettingsSliderSpec shows label and formatted value', () {
      final label = scene.buttons().firstWhere((b) => b.actionId == 'vol').label;
      expect(label, startsWith('Volume: '));
    });

    test('SettingsDropdownSpec shows label and placeholder when unset', () {
      final label = scene.buttons().firstWhere((b) => b.actionId == 'quality').label;
      expect(label, 'Quality: Select...');
    });

    test('SettingsListSpec shows label and selected item, not just the bare label', () async {
      await scene.optionsManager.setOption('region', 'eu');
      final label = scene.buttons().firstWhere((b) => b.actionId == 'region').label;
      expect(label, 'Region: Europe');
    });

    test('SettingsKeyBindingSpec shows label and binding prompt', () {
      final label = scene.buttons().firstWhere((b) => b.actionId == 'jump').label;
      expect(label, 'Jump: Press to bind...');
    });
  });
}
