import 'package:engine_core/engine_core.dart';
import 'package:engine_flutter/engine_flutter.dart';
import 'package:flutter/material.dart' hide Velocity;
import 'package:flutter_test/flutter_test.dart';

// Use prefix for engine_flutter's Text to avoid conflict with Flutter's Text widget
import 'package:engine_flutter/src/rendering/text.dart' as ef_text;

class _TestDialogueBoxScene extends DialogueBoxScene {
  _TestDialogueBoxScene(this.runner, this.stringTable);

  @override
  late final DialogueRunner runner;

  @override
  late final StringTable stringTable;

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

      scene = _TestDialogueBoxScene(DialogueRunner(graph, stringTable), stringTable);
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

      final sceneWithFlag = _TestDialogueBoxScene(DialogueRunner(graphWithFlag, stringTable), stringTable);
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

      // Simulate selecting first choice (index 0)
      scene.onChoiceSelected(
        DialogueChoice(textKey: 'choice_yes', onSelectEvent: 'give_reward', nextNodeId: 'rewarded'),
        world,
        controller,
      );

      expect(scene.runner.currentNode!.id, 'rewarded');
      expect(scene.runner.currentText, 'Great! Here is your reward.');
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

      final endScene = _TestDialogueBoxScene(DialogueRunner(endGraph, stringTable), stringTable);
      final world = World(width: 800, height: 600);
      registerCoreComponents(world);
      registerFlutterComponents(world);

      final gameState = GameState({});
      final controller = SceneController();

      await endScene.populate(world, controller, gameState);
      await tester.pump(const Duration(milliseconds: 16));

      endScene.onChoiceSelected(
        DialogueChoice(textKey: 'choice_yes', onSelectEvent: 'end_dialogue', nextNodeId: null),
        world,
        controller,
      );

      expect(endScene.runner.currentNode, isNull);
      expect(endScene.runner.currentText, isNull);
    });
  });
}