import '../ecs/entity.dart';
import '../ecs/world.dart';
import 'turn_components.dart';

/// A temporary modifier on a unit: `defending` (+defense), a poison that lowers
/// attack, a rallying cry that raises it. Plain data so it saves and an agent can
/// read it.
class StatusEffect {
  final String id;

  /// How many more of its *owner's* turn starts this survives. It is removed when
  /// the count reaches zero at a turn start, so `turns: 1` lasts until the
  /// owner's next turn begins -- the span "defend" needs to cover the enemy's
  /// whole reply.
  int turns;
  final int attack;
  final int defense;

  StatusEffect(this.id, {this.turns = 1, this.attack = 0, this.defense = 0});

  Map<String, dynamic> toJson() => {
    'id': id,
    'turns': turns,
    'attack': attack,
    'defense': defense,
  };
  factory StatusEffect.fromJson(Map<String, dynamic> json) => StatusEffect(
    json['id'] as String,
    turns: (json['turns'] as num?)?.toInt() ?? 1,
    attack: (json['attack'] as num?)?.toInt() ?? 0,
    defense: (json['defense'] as num?)?.toInt() ?? 0,
  );
}

/// The active [StatusEffect]s on a unit.
class StatusEffects {
  final List<StatusEffect> effects;
  StatusEffects([List<StatusEffect>? effects]) : effects = effects ?? [];

  int get attackBonus => effects.fold(0, (sum, e) => sum + e.attack);
  int get defenseBonus => effects.fold(0, (sum, e) => sum + e.defense);
  bool has(String id) => effects.any((e) => e.id == id);

  Map<String, dynamic> toJson() => {
    'effects': [for (final e in effects) e.toJson()],
  };
  factory StatusEffects.fromJson(Map<String, dynamic> json) => StatusEffects([
    for (final e in (json['effects'] as List? ?? const []))
      StatusEffect.fromJson((e as Map).cast<String, dynamic>()),
  ]);
}

/// The status id of a unit holding an overwatch stance (see `OverwatchOrder`).
const overwatchStatus = 'overwatch';

class StatusAppliedEvent {
  final EntityId entity;
  final String id;
  StatusAppliedEvent(this.entity, this.id);
}

class StatusExpiredEvent {
  final EntityId entity;
  final String id;
  StatusExpiredEvent(this.entity, this.id);
}

/// Gives [entity] [effect], replacing an existing effect with the same id (so
/// re-applying `defending` refreshes it rather than stacking).
void applyStatus(World world, EntityId entity, StatusEffect effect) {
  final store = world.storeOf<StatusEffects>();
  var statuses = store.get(entity);
  if (statuses == null) {
    statuses = StatusEffects();
    store.set(entity, statuses);
  }
  statuses.effects.removeWhere((e) => e.id == effect.id);
  statuses.effects.add(effect);
  world.events.emit(StatusAppliedEvent(entity, effect.id));
}

/// Counts down every status on [team]'s units at the start of that team's turn,
/// removing (and announcing) those that run out. Called by the turn clock.
void tickStatusEffects(World world, String team) {
  final teams = world.storeOf<Team>();
  final statuses = world.storeOf<StatusEffects>();
  for (var i = 0; i < statuses.length; i++) {
    final entity = statuses.entityAt(i);
    if (teams.get(entity)?.id != team) continue;
    final list = statuses.denseAt(i).effects;
    for (final e in list.toList()) {
      e.turns--;
      if (e.turns <= 0) {
        list.remove(e);
        world.events.emit(StatusExpiredEvent(entity, e.id));
      }
    }
  }
}
