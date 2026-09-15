import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load returns false and leaves bindings untouched when nothing was ever saved', () async {
    final controller = GamepadController(input: InputController());
    final defaultBindings = Map.of(controller.buttonBindings);

    final loaded = await GamepadBindingsStorage.load(controller);

    expect(loaded, isFalse);
    expect(controller.buttonBindings, defaultBindings);
  });

  test('save then load on a fresh controller restores the exact button bindings', () async {
    final original = GamepadController(input: InputController());
    original.buttonBindings
      ..clear()
      ..[5] = 'dash'
      ..[6] = 'jump';
    await GamepadBindingsStorage.save(original);

    final restored = GamepadController(input: InputController());
    final loaded = await GamepadBindingsStorage.load(restored);

    expect(loaded, isTrue);
    expect(restored.buttonBindings, {5: 'dash', 6: 'jump'});
  });

  test('save/load respects a custom storage key, keeping slots independent', () async {
    final a = GamepadController(input: InputController())
      ..buttonBindings.clear()
      ..buttonBindings[5] = 'dash';
    await GamepadBindingsStorage.save(a, key: 'profileA');

    final b = GamepadController(input: InputController());
    final loadedUnderWrongKey = await GamepadBindingsStorage.load(b, key: 'profileB');

    expect(loadedUnderWrongKey, isFalse);
  });
}
