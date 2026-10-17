import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'order.dart';
import 'carry.dart';
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
  world.events.on<AttackResolvedEvent>((e) => resolveAttack(world, e.attacker, e.target));
}

/// Applies one attack's damage: bonuses from `StatusEffects`, then
/// `UnitDamagedEvent`, and on 0 hp `UnitDefeatedEvent` and destruction. What
/// `installCombat` runs for every `AttackResolvedEvent`; call it directly when a
/// hit must land *immediately* rather than at the next event flush -- overwatch
/// uses this so a shot can stop the mover mid-path.
void resolveAttack(World world, EntityId attackerId, EntityId targetId) {
  final stats = world.storeOf<UnitStats>();
  final attacker = stats.get(attackerId);
  final target = stats.get(targetId);
  if (attacker == null || target == null || !world.entities.isAlive(targetId)) return;
  final statuses = world.storeOf<StatusEffects>();
  final amount = damageFor(
    attacker,
    target,
    attackBonus: statuses.get(attackerId)?.attackBonus ?? 0,
    defenseBonus: statuses.get(targetId)?.defenseBonus ?? 0,
  );
  target.hp = target.hp - amount < 0 ? 0 : target.hp - amount;
  world.events.emit(UnitDamagedEvent(attackerId, targetId, amount));
  if (target.hp == 0) {
    world.events.emit(UnitDefeatedEvent(targetId, world.storeOf<Team>().get(targetId)?.id));
    dropCarried(world, targetId);
    world.destroy(targetId);
  }
}

/// Eliminates teams with no surviving `UnitStats` unit and declares the
/// winner when exactly one team remains.
///
/// A team is only judged once it has been seen with units: a team that
/// never had any (a scripted neutral side) is not "eliminated" on tick
/// one, which would otherwise end the game immediately.
class WinConditionSystem extends System {
  final Set<String> _seen = {};
  final Set<String> _vipTeams = {};

  @override
  String get name => 'winCondition';

  @override
  void update(World world, double dt) {
    final state = world.storeOf<TurnState>();
    if (state.length == 0) return;
    final turn = state.denseAt(0);
    if (turn.winner != null) return;

    final alive = teamsStillInPlay(world, _vipTeams);
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


/// The teams that have not lost: they still have a unit, and - for a team that has
/// ever fielded a [Vip] - that Vip is still alive. [vipTeams] is the caller's
/// memory of which teams had one (a dead Vip is no longer in the world to find),
/// updated here.
Set<String> teamsStillInPlay(World world, Set<String> vipTeams) {
  final teams = world.storeOf<Team>();
  final stats = world.storeOf<UnitStats>();
  final vips = world.storeOf<Vip>();
  final withUnits = <String>{};
  final withVip = <String>{};
  for (var i = 0; i < teams.length; i++) {
    final e = teams.entityAt(i);
    final id = teams.denseAt(i).id;
    if (stats.has(e)) withUnits.add(id);
    if (vips.has(e)) withVip.add(id);
  }
  vipTeams.addAll(withVip);
  return {for (final t in withUnits) if (!vipTeams.contains(t) || withVip.contains(t)) t};
}
