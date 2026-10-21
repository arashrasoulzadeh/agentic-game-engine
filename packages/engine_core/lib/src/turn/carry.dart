import '../ecs/component_store.dart';
import '../ecs/entity.dart';
import '../ecs/world.dart';
import 'order.dart';
import 'turn_components.dart';
import 'turn_system.dart';
import 'combat.dart';

/// Marks a unit whose death loses the game for its team, however many other units
/// are left - the "escort" half of escort missions, and a king in a duel.
class Vip {
  const Vip();

  Map<String, dynamic> toJson() => {};
  factory Vip.fromJson(Map<String, dynamic> json) => const Vip();
}

/// A carryable objective item - a flag, a relic. It lies on the grid until a unit
/// of *another* team walks onto it, then rides with that unit until it is dropped
/// (its carrier dies) or delivered.
///
/// It has its own [col]/[row] rather than a `GridPosition`: anything with a
/// `GridPosition` counts as a unit for blocking, selection and fog, and a flag
/// must be walk-onto-able, not an obstacle.
class Flag {
  /// A name for UI and events ("red flag").
  final String id;

  /// The team it belongs to. Its own team cannot pick it up, and a carrier
  /// delivers it to *their own* [DeliveryZone].
  final String homeTeam;

  /// Where it returns to after delivery.
  final int homeCol;
  final int homeRow;

  /// The unit carrying it, or null when it lies on the ground.
  EntityId? carrier;

  /// Where it currently is (follows its carrier).
  int col;
  int row;

  Flag(
    this.id,
    this.homeTeam,
    this.homeCol,
    this.homeRow, {
    this.carrier,
    int? col,
    int? row,
  }) : col = col ?? homeCol,
       row = row ?? homeRow;

  Map<String, dynamic> toJson() => {
    'id': id,
    'homeTeam': homeTeam,
    'homeCol': homeCol,
    'homeRow': homeRow,
    'col': col,
    'row': row,
    'carrier': carrier,
  };
  factory Flag.fromJson(Map<String, dynamic> json) => Flag(
    json['id'] as String,
    json['homeTeam'] as String,
    (json['homeCol'] as num).toInt(),
    (json['homeRow'] as num).toInt(),
    carrier: (json['carrier'] as num?)?.toInt(),
    col: (json['col'] as num?)?.toInt(),
    row: (json['row'] as num?)?.toInt(),
  );
}

/// A cell where [team] scores by delivering a captured flag. Usually the team's own
/// base.
class DeliveryZone {
  final String team;
  final int col;
  final int row;
  const DeliveryZone(this.team, this.col, this.row);

  Map<String, dynamic> toJson() => {'team': team, 'col': col, 'row': row};
  factory DeliveryZone.fromJson(Map<String, dynamic> json) => DeliveryZone(
    json['team'] as String,
    (json['col'] as num).toInt(),
    (json['row'] as num).toInt(),
  );
}

/// Win-by-captures rule and running score, kept as world state so it saves.
class FlagRules {
  /// Captures that win the game.
  final int capturesToWin;

  /// Captures per team.
  final Map<String, int> captures;

  FlagRules({required this.capturesToWin, Map<String, int>? captures})
    : captures = captures ?? {};

  Map<String, dynamic> toJson() => {
    'capturesToWin': capturesToWin,
    'captures': captures,
  };
  factory FlagRules.fromJson(Map<String, dynamic> json) => FlagRules(
    capturesToWin: (json['capturesToWin'] as num).toInt(),
    captures: {
      for (final e in ((json['captures'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    },
  );
}

class FlagPickedUpEvent {
  final EntityId flag;
  final EntityId carrier;
  FlagPickedUpEvent(this.flag, this.carrier);
}

class FlagDroppedEvent {
  final EntityId flag;
  final EntityId formerCarrier;
  FlagDroppedEvent(this.flag, this.formerCarrier);
}

/// A carrier brought a flag to its team's [DeliveryZone]: [team] scores.
class FlagCapturedEvent {
  final EntityId flag;
  final String team;
  final int total;
  FlagCapturedEvent(this.flag, this.team, this.total);
}

/// Call after [unit] enters a cell: picks up a flag it is standing on, carries
/// any flag along, and scores one it delivers. Both order systems call this after
/// every step, so a pickup happens on the exact cell it is walked onto.
void onUnitMoved(World world, EntityId unit) {
  final flags = world.storeOf<Flag>();
  if (flags.length == 0) return;
  final at = world.storeOf<GridPosition>().get(unit);
  final team = world.storeOf<Team>().get(unit)?.id;
  if (at == null || team == null) return;

  for (var i = 0; i < flags.length; i++) {
    final flag = flags.denseAt(i);
    if (flag.carrier == unit) {
      flag.col = at.col;
      flag.row = at.row;
      _deliver(world, flags.entityAt(i), flag, team, at);
    } else if (flag.carrier == null &&
        flag.homeTeam != team &&
        flag.col == at.col &&
        flag.row == at.row &&
        !_carrying(flags, unit)) {
      flag.carrier = unit;
      world.events.emit(FlagPickedUpEvent(flags.entityAt(i), unit));
    }
  }
}

bool _carrying(ComponentStore<Flag> flags, EntityId unit) {
  for (var i = 0; i < flags.length; i++) {
    if (flags.denseAt(i).carrier == unit) return true;
  }
  return false;
}

void _deliver(
  World world,
  EntityId flagEntity,
  Flag flag,
  String team,
  GridPosition at,
) {
  final zones = world.storeOf<DeliveryZone>();
  for (var z = 0; z < zones.length; z++) {
    final zone = zones.denseAt(z);
    if (zone.team != team || zone.col != at.col || zone.row != at.row) continue;
    flag.carrier = null;
    flag.col = flag.homeCol;
    flag.row = flag.homeRow;
    final rules = world.storeOf<FlagRules>();
    var total = 0;
    if (rules.length > 0) {
      final r = rules.denseAt(0);
      total = r.captures[team] = (r.captures[team] ?? 0) + 1;
      final turn = turnStateOf(world);
      if (total >= r.capturesToWin && turn != null && turn.winner == null) {
        turn.winner = team;
        world.events.emit(VictoryEvent(team));
      }
    }
    world.events.emit(FlagCapturedEvent(flagEntity, team, total));
    return;
  }
}

/// Call when [unit] is about to be destroyed: any flag it carries is dropped on its
/// cell. `resolveAttack` does this for combat deaths.
void dropCarried(World world, EntityId unit) {
  final flags = world.storeOf<Flag>();
  for (var i = 0; i < flags.length; i++) {
    final flag = flags.denseAt(i);
    if (flag.carrier != unit) continue;
    flag.carrier = null;
    world.events.emit(FlagDroppedEvent(flags.entityAt(i), unit));
  }
}
