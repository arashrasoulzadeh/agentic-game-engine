import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DoneMarkerScene extends Scene {
  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {}
}

World _buildWorld() {
  final world = World(width: 800, height: 480);
  registerCoreComponents(world);
  registerFlutterComponents(world);
  return world;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('buttons() shows the current key label for each action, plus DONE', () async {
    final controller = InputController(); // arrowLeft -> "left", space -> "jump" by default
    final menu = RemapMenuScene(controller, const ['left', 'jump'], onDone: _DoneMarkerScene.new);
    await menu.populate(_buildWorld(), SceneController(), GameState());

    final labels = menu.buttons().map((b) => b.label).toList();
    // LogicalKeyboardKey.keyLabel is Flutter's own display string per
    // key -- a descriptive name for a non-printable key ("Arrow
    // Left"), but the literal character for a printable one (space's
    // keyLabel is a single " ", not the word "Space").
    expect(labels[0], contains('LEFT'));
    expect(labels[0], contains('Arrow Left'));
    expect(labels[1], contains('JUMP'));
    expect(labels[1], isNot(contains('unbound')));
    expect(labels.last, 'DONE');
  });

  test('an action with no bound key shows "(unbound)"', () async {
    final controller = InputController()..bindings.clear();
    final menu = RemapMenuScene(controller, const ['left'], onDone: _DoneMarkerScene.new);
    await menu.populate(_buildWorld(), SceneController(), GameState());

    expect(menu.buttons().first.label, contains('(unbound)'));
  });

  test('tapping an action button starts capturing the next key press', () async {
    final controller = InputController();
    final menu = RemapMenuScene(controller, const ['left'], onDone: _DoneMarkerScene.new);
    final world = _buildWorld();
    final scenes = SceneController();
    scenes.attach(loadScene: (_) {}, pushOverlay: (_) {}, popOverlay: () {});
    await menu.populate(world, scenes, GameState());

    menu.onButtonPressed('left', scenes);

    expect(controller.captureNextKeyDown, isNotNull);
  });

  test('capturing a key rebinds the action, saves it, and reloads the menu', () async {
    final controller = InputController();
    final menu = RemapMenuScene(controller, const ['left'], onDone: _DoneMarkerScene.new);
    final world = _buildWorld();
    Scene? loaded;
    final scenes = SceneController();
    scenes.attach(loadScene: (next) => loaded = next, pushOverlay: (_) {}, popOverlay: () {});
    await menu.populate(world, scenes, GameState());

    menu.onButtonPressed('left', scenes);
    controller.captureNextKeyDown!(LogicalKeyboardKey.keyA);
    // InputBindingsStorage.save is async but the capture callback is
    // synchronous (fire-and-forget) -- let its Future actually resolve
    // before checking persistence below.
    await Future<void>.delayed(Duration.zero);

    expect(controller.bindings[LogicalKeyboardKey.keyA], 'left');
    expect(controller.bindings.containsKey(LogicalKeyboardKey.arrowLeft), isFalse,
        reason: 'the old binding for "left" is replaced, not kept alongside the new one');
    expect(loaded, isA<RemapMenuScene>());

    final persisted = InputController()..bindings.clear();
    final wasLoaded = await InputBindingsStorage.load(persisted);
    expect(wasLoaded, isTrue);
    expect(persisted.bindings[LogicalKeyboardKey.keyA], 'left');
  });

  test('tapping DONE loads the scene onDone builds', () async {
    final controller = InputController();
    var doneCalls = 0;
    Scene buildDone() {
      doneCalls++;
      return _DoneMarkerScene();
    }

    final menu = RemapMenuScene(controller, const ['left'], onDone: buildDone);
    final world = _buildWorld();
    Scene? loaded;
    final scenes = SceneController();
    scenes.attach(loadScene: (next) => loaded = next, pushOverlay: (_) {}, popOverlay: () {});
    await menu.populate(world, scenes, GameState());

    menu.onButtonPressed('_remapDone', scenes);

    expect(doneCalls, 1);
    expect(loaded, isA<_DoneMarkerScene>());
  });

  test('handleTap on the DONE button triggers onButtonPressed via a real tap', () async {
    final controller = InputController();
    final menu = RemapMenuScene(controller, const ['left'], onDone: _DoneMarkerScene.new);
    final world = _buildWorld();
    Scene? loaded;
    final scenes = SceneController();
    scenes.attach(loadScene: (next) => loaded = next, pushOverlay: (_) {}, popOverlay: () {});
    await menu.populate(world, scenes, GameState());

    final buttons = world.storeOf<Button>();
    // DONE is the last spawned button.
    final doneEntity = buttons.entityAt(buttons.length - 1);
    final donePos = world.storeOf<Position>().get(doneEntity)!;
    menu.handleTap(world, scenes, Offset(donePos.x, donePos.y));

    expect(loaded, isA<_DoneMarkerScene>());
  });
}
