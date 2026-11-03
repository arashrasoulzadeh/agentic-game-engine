# Talk to an NPC

Walk up to a character, start a conversation, and let a choice change the
game. The dialogue graph and strings are [data](../concepts/dialogue.md); this
recipe is the gameplay glue around them.

Executed by `packages/zarvan_core/test/doc_examples_talk_to_npc_test.dart`.

## The setup

```dart
final world = World(width: 400, height: 200);
registerCoreComponents(world);
world.spawnWith([GameState({'name': 'Mira'})]);

final player = world.spawnAt(0, 0);
world.setName(player, 'player');
final elder = world.spawnAt(20, 0);
world.setName(elder, 'elder');

final graph = DialogueGraph.fromJson({
  'startNodeId': 'greet',
  'nodes': {
    'greet': {
      'id': 'greet',
      'textKey': 'elder.greet',
      'choices': [
        {'textKey': 'elder.accept', 'onSelectEvent': 'quest_accepted', 'nextNodeId': 'thanks'},
        {'textKey': 'elder.decline', 'onSelectEvent': 'quest_declined'},  // no nextNodeId: ends
      ],
    },
    'thanks': {'id': 'thanks', 'textKey': 'elder.thanks', 'choices': []},
  },
});
var talking = false;
final runner = DialogueRunner(
  graph: graph,
  onEnded: () => talking = false,
  stringTable: StringTable({
    'elder.greet': {'en': 'Will you help us, {name}?'},
    'elder.accept': {'en': 'Gladly'},
    'elder.decline': {'en': 'Not now'},
    'elder.thanks': {'en': 'Bless you.'},
  }),
);
```

## Start it when the player is close

```dart
world.addSystemFn('talk', (world, dt) {
  if (talking) return;                         // already talking
  final me = world.getComponent<Position>(world.find('player')!)!;
  final near = world.findNear(me.x, me.y, 32, exclude: world.find('player'));
  if (near.contains(world.find('elder'))) {
    runner.reset();
    talking = true;
  }
});
```

`world.find` looks entities up by the `name` set above (or by a level's
`name` key). `reset()` starts the conversation at `startNodeId`.

## Let a choice change the game

```dart
var questActive = false;
world.events.on<String>((event) {
  if (event == 'quest_accepted') questActive = true;
});

// In your UI, when the player presses choice N of `availableChoices`:
runner.advance(world, 0);
```

The event is delivered at the next flush (the end of `world.step`), so game
code reacts without the dialogue knowing it exists.

## Watch out for

- `advance` takes an index into `availableChoices`, not the node's full list.
- Every choice needs an `onSelectEvent` (the engine requires one), even when nothing listens. A conversation whose chosen choice has no `nextNodeId` ends and
  `onEnded` fires; clearing `talking` there is what lets the proximity system start it again.
- Put long text in the `StringTable`, never the node, so one graph serves
  every language.
