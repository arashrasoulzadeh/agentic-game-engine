// The samples in docs/concepts/dialogue.md, executed so the guide cannot drift.
import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  late World world;

  setUp(() {
    world = World(width: 800, height: 480);
    registerCoreComponents(world);
    world.storeOf<GameState>().set(world.spawn(), GameState({'name': 'Mira'}));
  });

  final strings = StringTable({
    'shop.greet': {'en': 'Welcome, {name}!'},
    'shop.buy': {'en': 'Buy a potion'},
    'shop.vip': {'en': 'The usual, please'},
    'shop.leave': {'en': 'Goodbye'},
    'shop.sold': {'en': 'Here you go.'},
  });

  DialogueGraph build() => DialogueGraph.fromJson({
        'startNodeId': 'greet',
        'nodes': {
          'greet': {
            'id': 'greet',
            'textKey': 'shop.greet',
            'speaker': 'Shopkeeper',
            'choices': [
              {'textKey': 'shop.buy', 'onSelectEvent': 'bought_potion', 'nextNodeId': 'sold'},
              {
                'textKey': 'shop.vip',
                'conditionEventFlag': 'is_vip',
                'onSelectEvent': 'vip_order',
                'nextNodeId': 'sold',
              },
              {'textKey': 'shop.leave', 'onSelectEvent': 'left_shop'},
            ],
          },
          'sold': {'id': 'sold', 'textKey': 'shop.sold', 'choices': []},
        },
      });

  test('run a conversation: text with {name}, conditional choices, events', () {
    final shown = <String>[];
    var ended = false;
    final runner = DialogueRunner(
      graph: build(),
      stringTable: strings,
      onNodeShown: (n) => shown.add(n.id),
      onEnded: () => ended = true,
    );
    final events = <String>[];
    world.events.on<String>(events.add);

    final view = WorldView(world);
    expect(runner.currentText(view), 'Welcome, Mira!');
    expect(runner.availableChoices(view).map((c) => c.textKey), ['shop.buy', 'shop.leave']);

    world.storeOf<GameState>().set(world.entities.all.first, GameState({'name': 'Mira', 'is_vip': true}));
    expect(runner.availableChoices(WorldView(world)).length, 3);

    expect(runner.advance(world, 0), isTrue);
    world.events.flush();
    expect(events, ['bought_potion']);
    expect(shown, ['sold']);
    expect(runner.currentText(WorldView(world)), 'Here you go.');

    // A node with no choices has nothing to advance; the dialogue is over when a
    // choice with no nextNodeId is taken.
    runner.reset();
    expect(runner.advance(world, 2), isFalse);
    expect(runner.isEnded, isTrue);
    expect(ended, isTrue);
  });

  test('the typewriter reveals text over the node duration', () {
    final graph = DialogueGraph(
      startNodeId: 'a',
      nodes: {
        'a': DialogueNode(id: 'a', textKey: 'shop.sold', typewriterDuration: 1, choices: []),
      },
    );
    final runner = DialogueRunner(graph: graph, stringTable: strings)..reset();
    final view = WorldView(world);
    expect(runner.visibleText(view), '');
    runner.updateTypewriter(0.5, view);
    final half = runner.visibleText(view)!;
    expect(half.length, inInclusiveRange(1, 'Here you go.'.length - 1));
    expect(runner.skip(view), isTrue, reason: 'skip finishes the reveal first');
    expect(runner.visibleText(view), 'Here you go.');
  });

  test('a conversation can be saved and resumed', () {
    final runner = DialogueRunner(graph: build(), stringTable: strings)..advance(world, 0);
    final saved = runner.toJson();
    final resumed = DialogueRunner.fromJson(saved, build(), strings);
    expect(resumed.currentNode!.id, 'sold');
  });
}
