import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'order.dart';
import 'status.dart';
import 'turn_components.dart';

/// Hit points and combat numbers for a turn-based unit. Lives in
/// `engine_core` rather than reusing `engine_platformer`'s `Health`
/// because a strategy package can't depend on the platformer one (DAG),
/// and these stats are plain data any genre can use.
class UnitStats {
  int hp;
  int maxHp;
  int attack;
  int defense;

  UnitStats({required this.maxHp, int? hp, this.attack = 1, this.defense = 0})
      : hp = hp ?? maxHp;

  Map<String, dynamic> toJson() =>
      {'hp': hp, 'maxHp': maxHp, 'attack': attack, 'defense': defense};
  factory UnitStats.fromJson(Map<String, dynamic> json) {
    final maxHp = (json['maxHp'] as num).toInt();
    return UnitStats(
      maxHp: maxHp,
      hp: (json['hp'] as num?)?.toInt() ?? maxHp,
      attack: (json['attack'] as num?)?.toInt() ?? 1,
      defense: (json['defense'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Per-unit reach and cost of an attack, overriding `OrderSystem`'s global
/// `attackRange`/`attackCost`: an archer with `range: 3`, a mage whose spell
/// costs 2 points. Absent, the unit uses the global values, so melee-only games
/// never need it.
class AttackProfile {
  /// Chebyshev distance (cells, diagonals count as one) the unit can attack from.
  int range;

  /// Action points one attack costs.
  int cost;

  AttackProfile({this.range = 1, this.cost = 1});

  Map<String, dynamic> toJson() => {'range': range, 'cost': cost};
  factory AttackProfile.fromJson(Map<String, dynamic> json) => AttackProfile(
        range: (json['range'] as num?)?.toInt() ?? 1,
        cost: (json['cost'] as num?)?.toInt() ?? 1,
      );
}

/// Emitted for each hit that lands.
class UnitDamagedEvent {
  final EntityId attacker;
  final EntityId target;
  final int amount;
  UnitDamagedEvent(this.attacker, this.target, this.amount);
}

/// Emitted when a unit reaches 0 hp, just before it is destroyed.
class UnitDefeatedEvent {
  final EntityId unit;
  final String? team;
  UnitDefeatedEvent(this.unit, this.team);
}

/// Emitted once when a single team remains.
class VictoryEvent {
  final String team;
  VictoryEvent(this.team);
}

/// Damage a hit does: attack minus defense, never below 1 so a chip
/// attack always makes progress and fights can't deadlock on stats.
///
/// [attackBonus]/[defenseBonus] are the summed `StatusEffects` modifiers.
int damageFor(UnitStats attacker, UnitStats target, {int attackBonus = 0, int defenseBonus = 0}) {
  final raw = attacker.attack + attackBonus - (target.defense + defenseBonus);
  return raw < 1 ? 1 : raw;
}

/// Wires `AttackResolvedEvent` (from `OrderSystem`) to damage. Call once
/// per world; kept as an install function like the engine's other event
/// wiring so order execution stays ignorant of any health model.
void installCombat(World world) {
  world.events.on<AttackResolvedEvent>((e) {
    final stats = world.storeOf<UnitStats>();
    final attacker = stats.get(e.attacker);
    final target = stats.get(e.target);
    if (attacker == null || target == null || !world.entities.isAlive(e.target)) return;
    final amount = damageFor(
      attacker,
      target,
      attackBonus: world.storeOf<StatusEffects>().get(e.attacker)?.attackBonus ?? 0,
      defenseBonus: world.storeOf<StatusEffects>().get(e.target)?.defenseBonus ?? 0,
    );
    target.hp = target.hp - amount < 0 ? 0 : target.hp - amount;
    world.events.emit(UnitDamagedEvent(e.attacker, e.target, amount));
    if (target.hp == 0) {
      world.events.emit(UnitDefeatedEvent(e.target, world.storeOf<Team>().get(e.target)?.id));
      world.destroy(e.target);
    }
  });
}

/// Eliminates teams with no surviving `UnitStats` unit and declares the
/// winner when exactly one team remains.
///
/// A team is only judged once it has been seen with units: a team that
/// never had any (a scripted neutral side) is not "eliminated" on tick
/// one, which would otherwise end the game immediately.
class WinConditionSystem extends System {
  final Set<String> _seen = {};

  @override
  String get name => 'winCondition';

  @override
  void update(World world, double dt) {
    final state = world.storeOf<TurnState>();
    if (state.length == 0) return;
    final turn = state.denseAt(0);
    if (turn.winner != null) return;

    final alive = <String>{};
    final teams = world.storeOf<Team>();
    final stats = world.storeOf<UnitStats>();
    for (var i = 0; i < teams.length; i++) {
      if (stats.has(teams.entityAt(i))) alive.add(teams.denseAt(i).id);
    }
    _seen.addAll(alive);
    for (final t in turn.order) {
      if (_seen.contains(t) && !alive.contains(t) && !turn.eliminated.contains(t)) {
        turn.eliminated.add(t);
      }
    }
    final remaining = [for (final t in turn.order) if (!turn.eliminated.contains(t)) t];
    if (remaining.length == 1 && _seen.length > 1) {
      turn.winner = remaining.single;
      world.events.emit(VictoryEvent(turn.winner!));
    }
  }
}
