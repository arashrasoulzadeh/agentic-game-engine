import '../ecs/world.dart';
import '../ecs/world_view.dart';
import 'game_state.dart';
import 'string_table.dart';

/// A single choice within a dialogue node.
class DialogueChoice {
  /// The localization key for the choice text.
  final String textKey;

  /// Optional world-state flag key that must be true for this choice to appear.
  /// Checked via `WorldView` against `GameState.data` — reuses the same
  /// flag/inventory lookup pattern as checkpoint helpers.
  final String? conditionEventFlag;

  /// Event to emit onto `world.events` when this choice is selected.
  /// Can be any JSON-serializable object (string, map, etc.).
  final Object onSelectEvent;

  /// The node ID to transition to after selecting this choice.
  /// If null, the dialogue ends.
  final String? nextNodeId;

  DialogueChoice({
    required this.textKey,
    this.conditionEventFlag,
    required this.onSelectEvent,
    this.nextNodeId,
  });

  Map<String, dynamic> toJson() => {
        'textKey': textKey,
        if (conditionEventFlag != null) 'conditionEventFlag': conditionEventFlag,
        'onSelectEvent': onSelectEvent,
        if (nextNodeId != null) 'nextNodeId': nextNodeId,
      };

  factory DialogueChoice.fromJson(Map<String, dynamic> json) => DialogueChoice(
        textKey: json['textKey'] as String,
        conditionEventFlag: json['conditionEventFlag'] as String?,
        onSelectEvent: json['onSelectEvent'],
        nextNodeId: json['nextNodeId'] as String?,
      );
}

/// A single node in a dialogue graph.
class DialogueNode {
  /// Unique identifier for this node within the graph.
  final String id;

  /// The localization key for the node's text.
  final String textKey;

  /// Available choices at this node.
  final List<DialogueChoice> choices;

  DialogueNode({
    required this.id,
    required this.textKey,
    required this.choices,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'textKey': textKey,
        'choices': choices.map((c) => c.toJson()).toList(),
      };

  factory DialogueNode.fromJson(Map<String, dynamic> json) => DialogueNode(
        id: json['id'] as String,
        textKey: json['textKey'] as String,
        choices: (json['choices'] as List)
            .map((c) => DialogueChoice.fromJson(c as Map<String, dynamic>))
            .toList(),
      );
}

/// A complete dialogue graph: a collection of nodes with a designated start.
class DialogueGraph {
  /// All nodes in the graph, keyed by their [id].
  final Map<String, DialogueNode> nodes;

  /// The node ID where the dialogue begins.
  final String startNodeId;

  DialogueGraph({
    required this.nodes,
    required this.startNodeId,
  });

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((k, v) => MapEntry(k, v.toJson())),
        'startNodeId': startNodeId,
      };

  factory DialogueGraph.fromJson(Map<String, dynamic> json) => DialogueGraph(
        nodes: (json['nodes'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, DialogueNode.fromJson(v as Map<String, dynamic>)),
        ),
        startNodeId: json['startNodeId'] as String,
      );

  /// Gets the starting node of this graph.
  DialogueNode get startNode => nodes[startNodeId]!;

  /// Gets a node by ID, or null if not found.
  DialogueNode? getNode(String id) => nodes[id];
}

/// Drives a dialogue graph at runtime — not a System (runs on demand,
/// not every tick). Holds the current position in the graph and exposes
/// actions to advance through it.
class DialogueRunner {
  final DialogueGraph graph;
  final StringTable stringTable;

  String? _currentNodeId;

  DialogueRunner(this.graph, this.stringTable) {
    _currentNodeId = graph.startNodeId;
  }

  /// The currently active node, or null if the dialogue has ended.
  DialogueNode? get currentNode => _currentNodeId != null ? graph.getNode(_currentNodeId!) : null;

  /// The resolved display text for the current node, or null if ended.
  String? get currentText => currentNode != null
      ? stringTable.resolve(currentNode!.textKey)
      : null;

  /// The available choices for the current node, filtered by world-state conditions.
  /// Returns only choices whose `conditionEventFlag` (if any) is true in the given
  /// [WorldView]'s `GameState.data`.
  List<DialogueChoice> availableChoices(WorldView view) {
    final node = currentNode;
    if (node == null) return [];
    final state = view.component<GameState>(0); // GameState is singleton on entity 0
    final flags = state?.data ?? {};
    return node.choices.where((choice) {
      if (choice.conditionEventFlag == null) return true;
      return flags[choice.conditionEventFlag] == true;
    }).toList();
  }

  /// Advances the dialogue by selecting a choice.
  /// Emits the choice's `onSelectEvent` onto [world.events], then moves to
  /// `nextNodeId` (or ends the dialogue if null).
  /// Returns true if the dialogue continues, false if it ended.
  bool advance(World world, int choiceIndex) {
    final choices = availableChoices(WorldView(world));
    if (choiceIndex < 0 || choiceIndex >= choices.length) return false;

    final choice = choices[choiceIndex];
    world.events.emit(choice.onSelectEvent);

    if (choice.nextNodeId != null) {
      _currentNodeId = choice.nextNodeId;
      return true;
    } else {
      _currentNodeId = null;
      return false;
    }
  }

  /// Resets the runner to the start node.
  void reset() => _currentNodeId = graph.startNodeId;

  Map<String, dynamic> toJson() => {
        'currentNodeId': _currentNodeId,
      };

  factory DialogueRunner.fromJson(Map<String, dynamic> json, DialogueGraph graph, StringTable stringTable) {
    final runner = DialogueRunner(graph, stringTable);
    runner._currentNodeId = json['currentNodeId'] as String?;
    return runner;
  }
}