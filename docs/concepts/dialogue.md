# Dialogue

A conversation is a **graph of nodes** (`DialogueGraph`), run by a `DialogueRunner` that
tracks where the player is, which choices are available, and the typewriter reveal. The
graph is plain JSON, so it is authored as data — by hand, by an agent, or in the
[studio's graph editor](../studio/user-guide.md#graphs).

Everything below is executed by
`packages/engine_core/test/doc_examples_dialogue_test.dart`.

## The graph

```dart
final graph = DialogueGraph.fromJson({
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
        {'textKey': 'shop.leave', 'onSelectEvent': 'left_shop'},   // no nextNodeId: ends
      ],
    },
    'sold': {'id': 'sold', 'textKey': 'shop.sold', 'choices': []},
  },
});
```

- Text is never written in the node. A node has a `textKey`, looked up in a **`StringTable`**
  (`{key: {locale: text}}`), so the same graph serves every language.
- A choice **ends the conversation** when it has no `nextNodeId`.
- Optional node fields: `speaker`, `portrait` (or `portraitAtlasId` + `portraitRegion`),
  `audioKey` / `localizedAudioKeys`, `typewriterDuration`, `skippable`, `autoAdvance`,
  `onShowEvent`.
- Optional choice fields, all of which hide the choice when not met: `conditionEventFlag`
  (a flag in `GameState`), `conditionInventory`, `conditionExpression`.

## Running it

```dart
final strings = StringTable({
  'shop.greet': {'en': 'Welcome, {name}!'},
  'shop.buy': {'en': 'Buy a potion'},
  // ...
});

final runner = DialogueRunner(
  graph: graph,
  stringTable: strings,
  onNodeShown: (node) => print('now showing ${node.id}'),
  onEnded: () => print('done'),
);

final view = WorldView(world);
runner.currentText(view);            // "Welcome, Mira!"
runner.availableChoices(view);       // only the choices whose conditions hold
runner.advance(world, 0);            // pick the first *available* choice
```

- `{name}` placeholders are filled from the world's **`GameState`** flags, so a dialogue
  can greet the player by a name the game stored earlier.
- `advance(world, index)` takes an index into `availableChoices`, not into the node's full
  list, so a hidden choice never shifts what the player pressed.
- Choosing emits the choice's `onSelectEvent` on `world.events` (as a `String` if you wrote
  a string), so gameplay reacts without the dialogue knowing about it:
  `world.events.on<String>((e) { if (e == 'bought_potion') ... })`. Like every event it is
  delivered at the next flush — the end of `world.step`.

## Typewriter and skipping

A node with `typewriterDuration > 0` reveals its text over that time. Call
`updateTypewriter(dt, view)` each frame and draw `visibleText(view)`. `skip(view)` first
finishes the reveal, and on the next call ends a node that has no choices.

!!! warning "autoAdvance"
    `autoAdvance` ends a node *with no choices* after `autoAdvanceDelay` using a real-time
    timer, not the simulation clock, so it does not follow pauses or a fixed timestep.
    Prefer driving the end of a conversation from your own systems if that matters.

## Saving

`runner.toJson()` records the current node and typewriter state;
`DialogueRunner.fromJson(json, graph, strings)` resumes it. The graph itself is data you
reload from its file.

## Drawing it

In a Flutter game, `DialogueBoxScene` (in `engine_flutter`) is an abstract overlay scene that
renders a runner's current text and choices as stacked buttons. Subclass it to supply the
runner and to react to the choices, then push it with `SceneController.pushOverlay`.

## From the studio's visual graphs

The studio edits dialogue as a node graph (`say` and `choice` nodes). `compileDialogueGraph`
turns such a `Graph` into the `DialogueGraph` above and throws a `DialogueCompileError` for
anything it does not support, rather than silently dropping it. Behavior trees and state
machines use the same canvas with their own compilers; see
[Content as data](content-as-data.md).
