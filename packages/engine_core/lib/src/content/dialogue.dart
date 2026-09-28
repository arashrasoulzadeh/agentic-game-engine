import '../ecs/world.dart';
import '../ecs/world_view.dart';
import 'game_state.dart';
import 'string_table.dart';
import 'inventory.dart';

/// A single choice within a dialogue node.
class DialogueChoice {
  /// The localization key for the choice text.
  final String textKey;

  /// Optional world-state flag key that must be true for this choice to appear.
  /// Checked via `WorldView` against `GameState.data` — reuses the same
  /// flag/inventory lookup pattern as checkpoint helpers.
  final String? conditionEventFlag;

  /// Optional inventory item condition: choice only appears if player has this item.
  /// Format: "itemId" or "itemId:count" (e.g., "key" or "coin:5")
  final String? conditionInventory;

  /// Optional expression condition for advanced logic.
  /// Format: "flag1 && flag2 || !flag3 && inventory:item:5"
  final String? conditionExpression;

  /// Event to emit onto `world.events` when this choice is selected.
  /// Can be any JSON-serializable object (string, map, etc.).
  final Object onSelectEvent;

  /// The node ID to transition to after selecting this choice.
  /// If null, the dialogue ends.
  final String? nextNodeId;

  /// Optional audio key for when this choice is selected.
  final String? onSelectAudioKey;

  /// Optional portrait to show when this choice is hovered/selected.
  final String? portrait;

  DialogueChoice({
    required this.textKey,
    this.conditionEventFlag,
    this.conditionInventory,
    this.conditionExpression,
    required this.onSelectEvent,
    this.nextNodeId,
    this.onSelectAudioKey,
    this.portrait,
  });

  Map<String, dynamic> toJson() => {
        'textKey': textKey,
        if (conditionEventFlag != null) 'conditionEventFlag': conditionEventFlag,
        if (conditionInventory != null) 'conditionInventory': conditionInventory,
        if (conditionExpression != null) 'conditionExpression': conditionExpression,
        'onSelectEvent': onSelectEvent,
        if (nextNodeId != null) 'nextNodeId': nextNodeId,
        if (onSelectAudioKey != null) 'onSelectAudioKey': onSelectAudioKey,
        if (portrait != null) 'portrait': portrait,
      };

  factory DialogueChoice.fromJson(Map<String, dynamic> json) => DialogueChoice(
        textKey: json['textKey'] as String,
        conditionEventFlag: json['conditionEventFlag'] as String?,
        conditionInventory: json['conditionInventory'] as String?,
        conditionExpression: json['conditionExpression'] as String?,
        onSelectEvent: json['onSelectEvent'],
        nextNodeId: json['nextNodeId'] as String?,
        onSelectAudioKey: json['onSelectAudioKey'] as String?,
        portrait: json['portrait'] as String?,
      );
}

/// A single node in a dialogue graph.
class DialogueNode {
  /// Unique identifier for this node within the graph.
  final String id;

  /// The localization key for the node's text.
  final String textKey;

  /// Optional speaker name/id — used for portrait lookup and voice acting.
  final String? speaker;

  /// Optional portrait sprite region key — displayed alongside text.
  /// Typically resolves to a sprite in the dialogue atlas.
  final String? portrait;

  /// Optional portrait atlas ID — if different from the main dialogue atlas.
  /// Allows portraits to be in a separate atlas from the dialogue box.
  final String? portraitAtlasId;

  /// Optional portrait region key in the portrait atlas.
  final String? portraitRegion;

  /// Optional audio key — played when this node is shown.
  /// Can be localized via StringTable (e.g., 'audio.voice.line1').
  final String? audioKey;

  /// Optional per-locale audio keys. If present and current locale matches,
  /// this overrides [audioKey]. Key is locale code (e.g., 'en', 'ja', 'es').
  final Map<String, String>? localizedAudioKeys;

  /// Typewriter effect duration in seconds. 0 = instant (default).
  /// If > 0, text is revealed character-by-character over this duration.
  final double typewriterDuration;

  /// Typewriter speed multiplier (1.0 = normal, 2.0 = 2x speed, etc.)
  final double typewriterSpeed;

  /// Whether this node can be skipped by player input (default true).
  final bool skippable;

  /// Whether this node auto-advances after typewriter completes (if no choices).
  final bool autoAdvance;

  /// Delay before auto-advance triggers (seconds), when [autoAdvance] is true.
  final double autoAdvanceDelay;

  /// Optional event to emit when this node is shown.
  final Object? onShowEvent;

  /// Available choices at this node.
  final List<DialogueChoice> choices;

  DialogueNode({
    required this.id,
    required this.textKey,
    this.speaker,
    this.portrait,
    this.portraitAtlasId,
    this.portraitRegion,
    this.audioKey,
    this.localizedAudioKeys,
    this.typewriterDuration = 0,
    this.typewriterSpeed = 1.0,
    this.skippable = true,
    this.autoAdvance = false,
    this.autoAdvanceDelay = 1.0,
    this.onShowEvent,
    required this.choices,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'textKey': textKey,
        if (speaker != null) 'speaker': speaker,
        if (portrait != null) 'portrait': portrait,
        if (portraitAtlasId != null) 'portraitAtlasId': portraitAtlasId,
        if (portraitRegion != null) 'portraitRegion': portraitRegion,
        if (audioKey != null) 'audioKey': audioKey,
        if (localizedAudioKeys != null && localizedAudioKeys.isNotEmpty) 'localizedAudioKeys': localizedAudioKeys,
        if (typewriterDuration > 0) 'typewriterDuration': typewriterDuration,
        if (typewriterSpeed != 1.0) 'typewriterSpeed': typewriterSpeed,
        if (!skippable) 'skippable': skippable,
        if (autoAdvance) 'autoAdvance': autoAdvance,
        if (autoAdvanceDelay != 1.0) 'autoAdvanceDelay': autoAdvanceDelay,
        if (onShowEvent != null) 'onShowEvent': onShowEvent,
        'choices': choices.map((c) => c.toJson()).toList(),
      };

  factory DialogueNode.fromJson(Map<String, dynamic> json) => DialogueNode(
        id: json['id'] as String,
        textKey: json['textKey'] as String,
        speaker: json['speaker'] as String?,
        portrait: json['portrait'] as String?,
        portraitAtlasId: json['portraitAtlasId'] as String?,
        portraitRegion: json['portraitRegion'] as String?,
        audioKey: json['audioKey'] as String?,
        localizedAudioKeys: json['localizedAudioKeys'] != null
            ? (json['localizedAudioKeys'] as Map).map((k, v) => MapEntry(k as String, v as String))
            : null,
        typewriterDuration: (json['typewriterDuration'] as num?)?.toDouble() ?? 0,
        typewriterSpeed: (json['typewriterSpeed'] as num?)?.toDouble() ?? 1.0,
        skippable: json['skippable'] as bool? ?? true,
        autoAdvance: json['autoAdvance'] as bool? ?? false,
        autoAdvanceDelay: (json['autoAdvanceDelay'] as num?)?.toDouble() ?? 1.0,
        onShowEvent: json['onShowEvent'],
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

  /// Optional metadata for the dialogue (title, author, version, etc.)
  final Map<String, dynamic>? metadata;

  DialogueGraph({
    required this.nodes,
    required this.startNodeId,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((k, v) => MapEntry(k, v.toJson())),
        'startNodeId': startNodeId,
        if (metadata != null) 'metadata': metadata,
      };

  factory DialogueGraph.fromJson(Map<String, dynamic> json) => DialogueGraph(
        nodes: (json['nodes'] as Map<String, dynamic>).map(
          (k, v) => MapEntry(k, DialogueNode.fromJson(v as Map<String, dynamic>)),
        ),
        startNodeId: json['startNodeId'] as String,
        metadata: json['metadata'] as Map<String, dynamic>?,
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

  /// Optional callback when a node is shown (for UI/audio triggers).
  final void Function(DialogueNode node)? onNodeShown;

  /// Optional callback when a choice is selected (for side effects).
  final void Function(DialogueChoice choice)? onChoiceSelected;

  /// Optional callback when dialogue ends.
  final void Function()? onEnded;

  String? _currentNodeId;
  int _typewriterProgress = 0;
  bool _typewriterComplete = true;
  double _typewriterTimer = 0;

  DialogueRunner({
    required this.graph,
    required this.stringTable,
    this.onNodeShown,
    this.onChoiceSelected,
    this.onEnded,
  }) {
    _currentNodeId = graph.startNodeId;
    _typewriterComplete = true;
  }

  /// The currently active node, or null if the dialogue has ended.
  DialogueNode? get currentNode => _currentNodeId != null ? graph.getNode(_currentNodeId!) : null;

  /// The resolved display text for the current node, with variable substitution.
  /// Returns null if dialogue has ended.
  String? currentText(WorldView view) {
    final node = currentNode;
    if (node == null) return null;
    String text = stringTable.resolve(node.textKey);
    return _substituteVariables(text, view);
  }

  /// Gets the audio key for the current node, considering localization.
  String? getCurrentAudioKey() {
    final node = currentNode;
    if (node == null) return null;
    
    // Try localized audio key first
    if (node.localizedAudioKeys != null && node.localizedAudioKeys!.isNotEmpty) {
      // TODO: Get current locale from somewhere (GameState, StringTable, etc.)
      // For now, try common locales
      for (final locale in ['en', 'en_US', 'en_GB', 'ja', 'ja_JP', 'es', 'es_ES', 'fr', 'fr_FR', 'de', 'de_DE', 'zh', 'zh_CN', 'zh_TW']) {
        if (node.localizedAudioKeys!.containsKey(locale)) {
          return node.localizedAudioKeys![locale];
        }
      }
    }
    return node.audioKey;
  }

  /// Gets the portrait atlas ID for the current node.
  String? getCurrentPortraitAtlasId() {
    final node = currentNode;
    if (node == null) return null;
    return node.portraitAtlasId;
  }

  /// Gets the portrait region for the current node.
  String? getCurrentPortraitRegion() {
    final node = currentNode;
    if (node == null) return null;
    return node.portraitRegion ?? node.portrait;
  }

  /// The resolved display text for the current node, with variable substitution.
  /// Returns null if dialogue has ended.
  String? currentText(WorldView view) {
    final node = currentNode;
    if (node == null) return null;
    String text = stringTable.resolve(node.textKey);
    return _substituteVariables(text, view);
  }

  /// The text currently visible (respects typewriter effect).
  /// If typewriter is active, returns only the revealed portion.
  String? visibleText(WorldView view) {
    final fullText = currentText(view);
    if (fullText == null) return null;
    if (_typewriterComplete) return fullText;
    return fullText.substring(0, _typewriterProgress.clamp(0, fullText.length));
  }

  /// Whether the typewriter effect is currently animating.
  bool get isTypewriterActive => !_typewriterComplete;

  /// Whether the current node's typewriter has completed.
  bool get isTypewriterComplete => _typewriterComplete;

  /// Whether the dialogue has ended.
  bool get isEnded => _currentNodeId == null;

  /// The available choices for the current node, filtered by world-state conditions.
  /// Returns only choices whose `conditionEventFlag`/`conditionInventory` are met.
  List<DialogueChoice> availableChoices(WorldView view) {
    final node = currentNode;
    if (node == null) return [];
    final state = view.component<GameState>(0);
    final flags = state?.data ?? {};
    final inventory = view.component<Inventory>(0);

    return node.choices.where((choice) {
      if (choice.conditionEventFlag != null) {
        if (flags[choice.conditionEventFlag] != true) return false;
      }
      if (choice.conditionInventory != null) {
        final parts = choice.conditionInventory!.split(':');
        final itemId = parts[0];
        final count = parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1;
        if (inventory == null) return false;
        final hasItem = inventory.items[itemId] ?? 0;
        if (hasItem < count) return false;
      }
      return true;
    }).toList();
  }

  String _substituteVariables(String text, WorldView view) {
    final state = view.component<GameState>(0);
    final flags = state?.data ?? {};
    final inventory = view.component<Inventory>(0);

    text = text.replaceAllMapped(
      RegExp(r'\{if\s+([^}]+)\}(.*?)\{/if\}'),
      (match) {
        final condition = match.group(1)!.trim();
        final content = match.group(2)!;
        bool show = false;
        if (condition.startsWith('!')) {
          final negated = condition.substring(1);
          show = !_checkCondition(negated, flags, inventory);
        } else {
          show = _checkCondition(condition, flags, inventory);
        }
        return show ? content : '';
      },
    );

    text = text.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (match) {
        final key = match.group(1)!;
        if (stringTable.hasKey(key)) {
          return stringTable.resolve(key);
        }
        if (flags.containsKey(key)) {
          final val = flags[key];
          return val is bool ? (val ? 'true' : 'false') : val.toString();
        }
        if (key.startsWith('inventory:')) {
          final itemId = key.substring('inventory:'.length);
          return inventory?.items[itemId]?.toString() ?? '0';
        }
        return match.group(0)!;
      },
    );

    return text;
  }

  bool _checkCondition(String condition, Map<String, dynamic> flags, Inventory? inventory) {
    if (condition.startsWith('inventory:')) {
      final itemId = condition.substring('inventory:'.length);
      return inventory?.items[itemId] != null && (inventory!.items[itemId] ?? 0) > 0;
    }
    return flags[condition] == true;
  }

  bool updateTypewriter(double dt, WorldView view) {
    final node = currentNode;
    if (node == null || node.typewriterDuration <= 0) {
      _typewriterComplete = true;
      return false;
    }
    if (_typewriterComplete) return false;

    _typewriterTimer += dt * node.typewriterSpeed;
    final fullText = currentText(view) ?? '';
    final totalChars = fullText.length;
    final progress = (_typewriterTimer / node.typewriterDuration * totalChars).floor();
    _typewriterProgress = progress.clamp(0, totalChars);

    if (_typewriterProgress >= totalChars) {
      _typewriterComplete = true;
      if (node.autoAdvance) {
        // Schedule auto-advance after delay
        Future.delayed(Duration(seconds: node.autoAdvanceDelay.ceil()), () {
          if (!_typewriterComplete) return; // Might have been interrupted
          final choices = availableChoices(view);
          if (choices.isEmpty) {
            _currentNodeId = null;
            onEnded?.call();
          }
        });
      }
      return false;
    }
    return true;
  }

  void completeTypewriter(WorldView view) {
    _typewriterComplete = true;
    _typewriterProgress = (currentText(view) ?? '').length;
  }

  bool skip(WorldView view) {
    if (isEnded) return false;
    final node = currentNode!;
    if (!node.skippable) return false;

    if (!_typewriterComplete && node.typewriterDuration > 0) {
      completeTypewriter(view);
      return true;
    }
    final choices = availableChoices(view);
    if (choices.isEmpty) {
      _currentNodeId = null;
      onEnded?.call();
      return true;
    }
    return false;
  }

  bool advance(World world, int choiceIndex) {
    final choices = availableChoices(WorldView(world));
    if (choiceIndex < 0 || choiceIndex >= choices.length) return false;

    final choice = choices[choiceIndex];
    onChoiceSelected?.call(choice);
    world.events.emit(choice.onSelectEvent);

    // Play choice selection audio if specified
    if (choice.onSelectAudioKey != null) {
      // TODO: Play audio via AudioManager
    }

    if (choice.nextNodeId != null) {
      _currentNodeId = choice.nextNodeId;
      _typewriterProgress = 0;
      _typewriterComplete = false;
      _typewriterTimer = 0;
      final newNode = graph.getNode(choice.nextNodeId!)!;
      onNodeShown?.call(newNode);
      return true;
    } else {
      _currentNodeId = null;
      onEnded?.call();
      return false;
    }
  }

  void reset() {
    _currentNodeId = graph.startNodeId;
    _typewriterProgress = 0;
    _typewriterComplete = false;
    _typewriterTimer = 0;
    final node = graph.startNode;
    onNodeShown?.call(node);
  }

  void replay() {
    reset();
  }

  Map<String, dynamic> toJson() => {
        'currentNodeId': _currentNodeId,
        'typewriterProgress': _typewriterProgress,
        'typewriterComplete': _typewriterComplete,
      };

  factory DialogueRunner.fromJson(
      Map<String, dynamic> json, DialogueGraph graph, StringTable stringTable,
      {void Function(DialogueNode)? onNodeShown,
       void Function(DialogueChoice)? onChoiceSelected,
       void Function()? onEnded}) {
    final runner = DialogueRunner(
      graph: graph,
      stringTable: stringTable,
      onNodeShown: onNodeShown,
      onChoiceSelected: onChoiceSelected,
      onEnded: onEnded,
    );
    runner._currentNodeId = json['currentNodeId'] as String?;
    runner._typewriterProgress = (json['typewriterProgress'] as num?)?.toInt() ?? 0;
    runner._typewriterComplete = (json['typewriterComplete'] as bool?) ?? false;
    return runner;
  }
}