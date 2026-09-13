import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load returns false and leaves bindings untouched when nothing was ever saved', () async {
    final controller = InputController();
    final defaultBindings = Map.of(controller.bindings);

    final loaded = await InputBindingsStorage.load(controller);

    expect(loaded, isFalse);
    expect(controller.bindings, defaultBindings);
  });

  test('save then load on a fresh controller restores the exact bindings', () async {
    final original = InputController();
    original.bindings
      ..clear()
      ..[LogicalKeyboardKey.keyW] = 'up'
      ..[LogicalKeyboardKey.keyA] = 'left';
    await InputBindingsStorage.save(original);

    final restored = InputController();
    final loaded = await InputBindingsStorage.load(restored);

    expect(loaded, isTrue);
    expect(restored.bindings, {
      LogicalKeyboardKey.keyW: 'up',
      LogicalKeyboardKey.keyA: 'left',
    });
  });

  test('save/load respects a custom storage key, keeping slots independent', () async {
    final a = InputController()
      ..bindings.clear()
      ..bindings[LogicalKeyboardKey.keyW] = 'up';
    await InputBindingsStorage.save(a, key: 'profileA');

    final b = InputController();
    final loadedUnderWrongKey = await InputBindingsStorage.load(b, key: 'profileB');

    expect(loadedUnderWrongKey, isFalse);
  });
}
