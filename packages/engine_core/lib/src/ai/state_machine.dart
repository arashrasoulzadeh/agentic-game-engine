import '../ecs/behavior.dart';
import '../ecs/action.dart';
import '../ecs/entity.dart';
import '../ecs/world_view.dart';
import '../ecs/world.dart';
import '../ecs/system.dart';
import '../ai/ai_state.dart';
import 'behavior_tree.dart';

/// Represents a state in a finite state machine.
class FSMState {
  final String name;
  final BTNode? behaviorTree;
  final Behavior? behavior;
  final Map<String, FSMTransition> transitions;

  FSMState({
    required this.name,
    this.behaviorTree,
    this.behavior,
    Map<String, FSMTransition>? transitions,
  }) : transitions = transitions ?? {};

  /// Adds a transition to another state with a condition.
  void addTransition(String toState, bool Function(BTContext) condition) {
    transitions[toState] = FSMTransition(toState, condition);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'behaviorTree': behaviorTree?.toJson(),
    'behaviorId': behavior != null ? 'custom' : null,
    'transitions': transitions.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory FSMState.fromJson(
    Map<String, dynamic> json,
    BehaviorRegistry registry, {
    Map<String, bool Function(BTContext)>? conditions,
  }) {
    BTNode? tree;
    Behavior? behavior;
    if (json['behaviorTree'] != null) {
      tree = BTNode.fromJson(json['behaviorTree'] as Map<String, dynamic>);
    } else if (json['behaviorId'] != null) {
      // Custom behavior - would need to be resolved from registry
      behavior = registry.resolve(json['behaviorId'] as String);
    }
    final transitions = <String, FSMTransition>{};
    if (json['transitions'] != null) {
      final trans = json['transitions'] as Map<String, dynamic>;
      for (final entry in trans.entries) {
        transitions[entry.key] = FSMTransition.fromJson(
          entry.value as Map<String, dynamic>,
          conditions: conditions,
        );
      }
    }
    return FSMState(
      name: json['name'] as String,
      behaviorTree: tree,
      behavior: behavior,
      transitions: transitions,
    );
  }
}

/// A transition between states with a condition.
class FSMTransition {
  final String toState;
  final bool Function(BTContext) condition;

  /// The name this transition's [condition] is bound by when the machine is loaded from
  /// JSON (see [FSMTransition.fromJson]). Null for a condition written directly in Dart.
  final String? conditionName;

  FSMTransition(this.toState, this.condition, {this.conditionName});

  /// Conditions are code, so only their *name* is serialized; the game supplies the
  /// function for each name when it loads the machine.
  Map<String, dynamic> toJson() => {
    'toState': toState,
    if (conditionName != null) 'condition': conditionName,
  };

  /// Loads a transition, binding its named `condition` to the function in [conditions].
  /// A name with no function bound -- or no name -- gives a transition that never fires,
  /// so a typo in a name leaves the machine idle rather than throwing mid-game.
  factory FSMTransition.fromJson(
    Map<String, dynamic> json, {
    Map<String, bool Function(BTContext)>? conditions,
  }) {
    final name = json['condition'] as String?;
    return FSMTransition(
      json['toState'] as String,
      (name == null ? null : conditions?[name]) ?? (context) => false,
      conditionName: name,
    );
  }
}

/// A finite state machine that can run behavior trees or custom behaviors per state.
class StateMachine {
  final String id;
  final Map<String, FSMState> states;
  String currentStateName;
  FSMState? _previousState;

  StateMachine({
    required this.id,
    required Map<String, FSMState> states,
    String? initialState,
  }) : states = states,
       currentStateName = initialState ?? states.keys.first;

  FSMState get currentState => states[currentStateName]!;

  /// Attempts to transition to a new state if its condition is met.
  bool tryTransition(BTContext context) {
    final currentState = this.currentState;
    for (final entry in currentState.transitions.entries) {
      if (entry.value.condition(context)) {
        _previousState = currentState;
        currentStateName = entry.key;
        return true;
      }
    }
    return false;
  }

  /// Forces a transition to a specific state.
  void forceTransition(String toState) {
    if (states.containsKey(toState)) {
      _previousState = currentState;
      currentStateName = toState;
    }
  }

  /// Returns the previous state name, if any.
  String? get previousStateName => _previousState?.name;

  /// Ticks the current state's behavior tree or behavior.
  BTStatus tick(BTContext context) {
    final state = currentState;
    if (state.behaviorTree != null) {
      return state.behaviorTree!.tick(context);
    }
    if (state.behavior != null) {
      final action = state.behavior!.decide(context.view, context.entity);
      action.apply(context.view.world);
      return BTStatus.running; // Custom behaviors run continuously
    }
    return BTStatus.success;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'currentState': currentStateName,
    'states': states.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory StateMachine.fromJson(
    Map<String, dynamic> json,
    BehaviorRegistry registry, {
    Map<String, bool Function(BTContext)>? conditions,
  }) {
    final states = <String, FSMState>{};
    final statesJson = json['states'] as Map<String, dynamic>;
    for (final entry in statesJson.entries) {
      states[entry.key] = FSMState.fromJson(
        entry.value as Map<String, dynamic>,
        registry,
        conditions: conditions,
      );
    }
    return StateMachine(
      id: json['id'] as String,
      states: states,
      initialState: json['currentState'] as String?,
    );
  }
}

/// Behavior that runs a StateMachine.
class StateMachineBehavior implements Behavior {
  final StateMachine stateMachine;
  final BehaviorRegistry registry;

  StateMachineBehavior({required this.stateMachine, required this.registry});

  @override
  Action decide(WorldView view, EntityId self) =>
      _RunStateMachineAction(stateMachine, registry, self);
}

/// Action that runs the state machine for one tick.
class _RunStateMachineAction implements Action {
  final StateMachine stateMachine;
  final BehaviorRegistry registry;
  final EntityId entity;

  _RunStateMachineAction(this.stateMachine, this.registry, this.entity);

  @override
  void apply(World world) {
    final aiState = world.storeOf<AIState>().get(entity);
    if (aiState == null) return;

    // Get or create the state machine's blackboard
    final rawBlackboard = aiState.memory['_fsm_blackboard'];
    final blackboard =
        (rawBlackboard as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    aiState.memory['_fsm_blackboard'] = blackboard;

    final view = WorldView(world);
    final context = BTContext(view, entity, blackboard: blackboard)
      ..set('_bt_registry', registry)
      ..set('_time', world.tick.toDouble())
      ..set('_dt', world.deltaTime);

    // Try to transition
    stateMachine.tryTransition(context);

    // Tick the current state
    stateMachine.tick(context);

    // Store updated blackboard
    aiState.memory['_fsm_blackboard'] = blackboard;
  }
}

/// System that runs state machines stored as JSON in `AIState.memory['_fsm_root']`.
///
/// [conditions] binds the condition names in that JSON to functions (see
/// [FSMTransition.fromJson]). The machine's current state is written back to the JSON
/// after each tick, so a transition sticks instead of resetting next frame.
class StateMachineSystem implements System {
  final BehaviorRegistry registry;
  final Map<String, bool Function(BTContext)> conditions;

  StateMachineSystem(this.registry, {this.conditions = const {}});

  @override
  String get name => 'stateMachine';

  @override
  void update(World world, double dt) {
    final states = world.storeOf<AIState>();
    for (var i = 0; i < states.length; i++) {
      final entity = states.entityAt(i);
      final state = states.denseAt(i);

      final rootJson = (state.memory['_fsm_root'] as Map?)
          ?.cast<String, dynamic>();
      if (rootJson == null) continue;

      final stateMachine = StateMachine.fromJson(
        rootJson,
        registry,
        conditions: conditions,
      );

      final rawBlackboard = state.memory['_fsm_blackboard'];
      final blackboard =
          (rawBlackboard as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      state.memory['_fsm_blackboard'] = blackboard;

      final view = WorldView(world);
      final context = BTContext(view, entity, blackboard: blackboard)
        ..set('_bt_registry', registry)
        ..set('_time', world.tick.toDouble())
        ..set('_dt', dt);

      // Try to transition
      stateMachine.tryTransition(context);

      // Tick the current state
      stateMachine.tick(context);

      // Store updated blackboard
      state.memory['_fsm_blackboard'] = blackboard;
      rootJson['currentState'] = stateMachine.currentStateName;
    }
  }
}
