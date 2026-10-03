import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

// Use prefix for engine_flutter's Text to avoid conflict with Flutter's Text widget
import 'package:engine_flutter/src/rendering/text.dart' as ef_text;

class _TestDialogueBoxScene extends DialogueBoxScene {
  _TestDialogueBoxScene(this.runner, this.stringTable, {this.atlasIds = const []});

  @override
  late final DialogueRunner runner;

  @override
  late final StringTable stringTable;

  final List<String> atlasIds;

  @override
  List<String> get requiredAtlasIds => atlasIds;

  @override
  Future<void> populate(World world, SceneController scenes, GameState state) async {
    await super.populate(world, scenes, state);
  }
}

void main() {
  group('DialogueBoxScene', () {
    late StringTable stringTable;
    late DialogueGraph graph;
    late _TestDialogueBoxScene scene;

    setUp(() {
      stringTable = StringTable({
        'greeting': {'en': 'Hello, {name}!'},
        'choice_yes': {'en': 'Yes, please!'},
        'choice_no': {'en': 'No, thanks.'},
        'node2_text': {'en': 'Great! Here is your reward.'},
        'node3_text': {'en': 'Maybe next time.'},
      }, locale: 'en');

      graph = DialogueGraph(
        nodes: {
          'start': DialogueNode(
            id: 'start',
            textKey: 'greeting',
            choices: [
              DialogueChoice(textKey: 'choice_yes', onSelectEvent: 'give_reward', nextNodeId: 'rewarded'),
              DialogueChoice(textKey: 'choice_no', onSelectEvent: 'decline_reward', nextNodeId: 'declined'),
            ],
          ),
          'rewarded': DialogueNode(id: 'rewarded', textKey: 'node2_text', choices: []),
          'declined': DialogueNode(id: 'declined', textKey: 'node3_text', choices: []),
        },
        startNodeId: 'start',
      );

      scene = _TestDialogueBoxScene(DialogueRunner(graph: graph, stringTable: stringTable), stringTable);
    });

    testWidgets('renders dialogue text and choice buttons', (tester) async {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final gameState = GameState({});
      final controller = SceneController();

      // Build the scene's widget tree
      final sceneWidget = Builder(
        builder: (context) {
          return MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 600,
                child: EngineView(
                  world: world,
                  atlasRegistry: AtlasRegistry(),
                  camera: Camera(),
                  backgroundColor: const Color(0xFF000000),
                ),
              ),
            ),
          );
        },
      );

      await tester.pumpWidget(sceneWidget);
      await tester.pump(const Duration(milliseconds: 16));

      // Populate the scene
      await scene.populate(world, controller, gameState);
      await tester.pump(const Duration(milliseconds: 16));

      // Check that dialogue text entity was created with correct text
      final view = WorldView(world);
      final textEntities = view.entitiesWith<ef_text.Text>().toList();
      expect(textEntities, isNotEmpty);

      final textComponent = world.storeOf<ef_text.Text>().get(textEntities.first)!;
      expect(textComponent.text, 'Hello, {name}!');
    });

    testWidgets(
        'positions dialogue background/text against the fixed screen '
        'reference, not World.width/height (regression: a large level '
        'world used to send the dialogue background and text thousands '
        'of pixels off-screen, leaving only the portrait -- positioned '
        'with a separate literal constant -- visible)', (tester) async {
      // Mirrors test_game's prison level, which is much larger than any
      // real viewport -- this is exactly the shape of world that
      // triggered the bug.
      final world = World(width: 4000, height: 1440);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final gameState = GameState({});
      final controller = SceneController();

      await scene.populate(world, controller, gameState);

      final view = WorldView(world);
      final textEntities = view.entitiesWith<ef_text.Text>().toList();
      expect(textEntities, isNotEmpty);
      final textPos = world.storeOf<Position>().get(textEntities.first)!;

      // Screen-space reference is a fixed 800x600, regardless of the
      // World's own (much larger) dimensions -- see
      // DialogueBoxScene._kScreenWidth/_kScreenHeight.
      expect(textPos.x, 400); // _kScreenWidth / 2
      expect(textPos.y, 480); // _kScreenHeight - 120
    });

    testWidgets('buttons() returns correct number of choices', (tester) async {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final gameState = GameState({});
      final controller = SceneController();

      await scene.populate(world, controller, gameState);

      final buttons = scene.buttons();
      expect(buttons.length, 2);
      expect(buttons[0].label, 'Yes, please!');
      expect(buttons[1].label, 'No, thanks.');
    });

    testWidgets('availableChoices respects conditionEventFlag', (tester) async {
      final graphWithFlag = DialogueGraph(
        nodes: {
          'start': DialogueNode(
            id: 'start',
            textKey: 'greeting',
            choices: [
              DialogueChoice(
                textKey: 'choice_yes',
                onSelectEvent: 'give_reward',
                nextNodeId: 'rewarded',
                conditionEventFlag: 'met_npc',
              ),
              DialogueChoice(
                textKey: 'choice_no',
                onSelectEvent: 'decline_reward',
                nextNodeId: 'declined',
              ),
            ],
          ),
          'rewarded': DialogueNode(id: 'rewarded', textKey: 'node2_text', choices: []),
          'declined': DialogueNode(id: 'declined', textKey: 'node3_text', choices: []),
        },
        startNodeId: 'start',
      );

      final sceneWithFlag = _TestDialogueBoxScene(DialogueRunner(graph: graphWithFlag, stringTable: stringTable), stringTable);
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final gameState = GameState({});
      final controller = SceneController();

      await sceneWithFlag.populate(world, controller, gameState);

      // No flag set - only 1 choice (the unconditional one)
      var buttons = sceneWithFlag.buttons();
      expect(buttons.length, 1);
      expect(buttons[0].label, 'No, thanks.');

      // Add flag
      world.storeOf<GameState>().set(0, GameState({'met_npc': true}));
      await tester.pump(const Duration(milliseconds: 16));

      buttons = sceneWithFlag.buttons();
      expect(buttons.length, 2);
    });

    testWidgets('onChoiceSelected advances dialogue and emits event', (tester) async {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final gameState = GameState({});
      final controller = SceneController();

      await scene.populate(world, controller, gameState);
      await tester.pump(const Duration(milliseconds: 16));

      // `_choiceIndex` looks the choice up by identity within the current
      // node, so it must be the actual instance from the graph, not an
      // equal-looking copy.
      final choice = scene.runner.currentNode!.choices.first;
      scene.onChoiceSelected(choice, world, controller);

      expect(scene.runner.currentNode!.id, 'rewarded');
      expect(scene.runner.currentText(WorldView(world)), 'Great! Here is your reward.');
    });

    testWidgets('onChoiceSelected ends dialogue when nextNodeId is null', (tester) async {
      final endGraph = DialogueGraph(
        nodes: {
          'start': DialogueNode(
            id: 'start',
            textKey: 'greeting',
            choices: [
              DialogueChoice(textKey: 'choice_yes', onSelectEvent: 'end_dialogue', nextNodeId: null),
            ],
          ),
        },
        startNodeId: 'start',
      );

      final endScene = _TestDialogueBoxScene(DialogueRunner(graph: endGraph, stringTable: stringTable), stringTable);
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final gameState = GameState({});
      final controller = SceneController();
      var popped = false;
      controller.attach(
        pushOverlay: (_) {},
        popOverlay: () => popped = true,
        loadScene: (_) {},
      );

      await endScene.populate(world, controller, gameState);
      await tester.pump(const Duration(milliseconds: 16));

      final choice = endScene.runner.currentNode!.choices.first;
      endScene.onChoiceSelected(choice, world, controller);

      expect(popped, isTrue);

      expect(endScene.runner.currentNode, isNull);
      expect(endScene.runner.currentText(WorldView(world)), isNull);
    });

    testWidgets(
        'loadAssets registers the generated choice-button atlas '
        '(regression: overriding loadAssets without calling '
        "super.loadAssets() left every choice button's Sprite pointing "
        'at an unregistered kMenuButtonAtlasId -- AtlasRegistry.resolve '
        'throws for that uncaught mid-paint, which silently killed the '
        "dialogue text and buttons drawn later in the same frame, i.e. "
        'the actual "dialogue box renders, no text, cannot pick a '
        'choice" bug)', (tester) async {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final gameState = GameState({});
      final controller = SceneController();

      // loadAssets runs after populate in GameRunner._load (see
      // DialogueBoxScene.loadAssets's own doc comment) -- populate
      // first so buttons() has real choices to bake labels from.
      await scene.populate(world, controller, gameState);
      final registry = await scene.loadAssets();

      expect(registry.has(kMenuButtonAtlasId), isTrue);
    });

    testWidgets(
        "update() re-spawns choice buttons once the current node changes "
        '(regression: ButtonMenuScene.populate only ever spawns buttons '
        'once, so a tap that correctly advanced the DialogueRunner to a '
        "new node used to leave the previous node's now-stale buttons "
        'on screen -- the actual "dialogue advances internally but the '
        'player can\'t act on it / can\'t skip" bug)', (tester) async {
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final gameState = GameState({});
      final controller = SceneController();

      await scene.populate(world, controller, gameState);
      await tester.pump(const Duration(milliseconds: 16));

      final buttonsBefore = world.storeOf<Button>().length;
      final actionIdsBefore = scene.buttons().map((b) => b.actionId).toSet();
      expect(actionIdsBefore, {'choice_yes', 'choice_no'});

      // Advance to a node with a different set of choices (none here,
      // since 'rewarded' is a dead end) by going through the same path
      // a real tap takes: onButtonPressed -> onChoiceSelected -> advance.
      scene.onButtonPressed('choice_yes', controller);
      scene.update(0.016, world);

      expect(scene.runner.currentNode!.id, 'rewarded');
      expect(buttonsBefore, 2);
      // 'rewarded' has no choices -- the old node's buttons must be
      // actually destroyed, not just superseded by new ones left
      // stacked on top underneath.
      expect(scene.buttons(), isEmpty);
      expect(world.storeOf<Button>().length, 0);
    });

    test('loadAssets skips a missing atlas instead of throwing', () async {
      final scene = _TestDialogueBoxScene(
        DialogueRunner(graph: graph, stringTable: stringTable),
        stringTable,
        atlasIds: const ['does_not_exist'],
      );

      final registry = await scene.loadAssets();

      expect(registry, isNotNull);
      expect(registry.has('does_not_exist'), isFalse);
    });
  });
}