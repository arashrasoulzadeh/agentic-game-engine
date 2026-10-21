import '../ecs/entity.dart';
import '../ecs/world.dart';
import 'turn_components.dart';

/// What a team has unlocked by name, independent of its buildings: set by game code (a research
/// finished, a scripted reward, a campaign carry-over). One per team, on any entity.
class TechState {
  /// The team this belongs to.
  final String team;

  /// Names of the unlocked technologies.
  final Set<String> researched;

  TechState(this.team, {Set<String>? researched})
    : researched = researched ?? {};

  Map<String, dynamic> toJson() => {
    'team': team,
    'researched': researched.toList()..sort(),
  };
  factory TechState.fromJson(Map<String, dynamic> json) => TechState(
    json['team'] as String,
    researched: {
      for (final t in (json['researched'] as List? ?? const [])) t as String,
    },
  );
}

/// On a building: while it stands **and is finished**, its team has these technologies. How an
/// "age" or a "barracks unlocks knights" rule is written - the building *is* the prerequisite, and
/// losing it takes the unlock away again.
class Provides {
  final Set<String> tech;

  Provides(Set<String> tech) : tech = {...tech};

  Map<String, dynamic> toJson() => {'tech': tech.toList()..sort()};
  factory Provides.fromJson(Map<String, dynamic> json) => Provides({
    for (final t in (json['tech'] as List? ?? const [])) t as String,
  });
}

/// Everything [team] currently has: its [TechState]s plus whatever its finished buildings [Provides].
Set<String> availableTech(World world, String team) {
  final out = <String>{};
  final states = world.storeOf<TechState>();
  for (var i = 0; i < states.length; i++) {
    if (states.denseAt(i).team == team)
      out.addAll(states.denseAt(i).researched);
  }
  final provides = world.storeOf<Provides>();
  final teams = world.storeOf<Team>();
  final building = world.storeOf<Construction>();
  for (var i = 0; i < provides.length; i++) {
    final e = provides.entityAt(i);
    if (teams.get(e)?.id == team && !building.has(e))
      out.addAll(provides.denseAt(i).tech);
  }
  return out;
}

/// The members of [requires] that [team] does not have yet (empty when it may proceed).
Set<String> missingTech(World world, String team, Iterable<String> requires) {
  final need = requires.toSet();
  if (need.isEmpty) return need;
  return need.difference(availableTech(world, team));
}

/// Unlocks [tech] for [team] by name. Creates the team's [TechState] if it has none.
void grantTech(World world, String team, String tech) {
  final states = world.storeOf<TechState>();
  for (var i = 0; i < states.length; i++) {
    if (states.denseAt(i).team == team) {
      states.denseAt(i).researched.add(tech);
      return;
    }
  }
  states.set(world.spawn(), TechState(team, researched: {tech}));
}

/// A producer has units queued but its team lacks the technologies it requires. Emitted once per
/// lock (not every tick), so a UI can say "needs: barracks".
class ProductionLockedEvent {
  final EntityId producer;
  final Set<String> missing;
  ProductionLockedEvent(this.producer, this.missing);
}
