import 'dart:math' as math;

import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'formation.dart';
import 'grid_navigation.dart';
import 'order.dart';
import 'tech.dart';
import 'turn_components.dart';

/// One team's stockpile of resources, plus what it earns per second.
///
/// Amounts are whole numbers (a "wood" count a player reads); income is fractional
/// per second, and the fractional remainder is carried between ticks so 0.5/s
/// really yields one unit every two seconds rather than rounding to zero.
class Treasury {
  final String team;
  final Map<String, int> amounts;

  /// Resource per second by name, e.g. `{'gold': 2.5}`.
  final Map<String, double> incomePerSecond;

  /// Fractional resource earned but not yet a whole unit. Serialized: a snapshot
  /// restored without it would pay out a tick early or late and diverge from the
  /// original (rollback, replay and lockstep all depend on identical state).
  final Map<String, double> carry;

  Treasury(
    this.team, {
    Map<String, int>? amounts,
    Map<String, double>? incomePerSecond,
    Map<String, double>? carry,
  }) : amounts = amounts ?? {},
       incomePerSecond = incomePerSecond ?? {},
       carry = carry ?? {};

  int of(String resource) => amounts[resource] ?? 0;

  bool canAfford(Map<String, int> cost) =>
      cost.entries.every((e) => of(e.key) >= e.value);

  /// Deducts [cost] if affordable, all or nothing. Returns whether it did.
  bool spend(Map<String, int> cost) {
    if (!canAfford(cost)) return false;
    for (final e in cost.entries) {
      amounts[e.key] = of(e.key) - e.value;
    }
    return true;
  }

  void add(String resource, int amount) =>
      amounts[resource] = of(resource) + amount;

  /// Accrues [dt] seconds of income.
  void accrue(double dt) {
    for (final e in incomePerSecond.entries) {
      final total = (carry[e.key] ?? 0) + e.value * dt;
      // Epsilon: 0.5/s over four 0.5 s steps must yield exactly one, not 0.9999999.
      final whole = (total + 1e-9).floor();
      if (whole > 0) add(e.key, whole);
      carry[e.key] = total - whole;
    }
  }

  Map<String, dynamic> toJson() => {
    'team': team,
    'amounts': amounts,
    'incomePerSecond': incomePerSecond,
    'carry': carry,
  };
  factory Treasury.fromJson(Map<String, dynamic> json) => Treasury(
    json['team'] as String,
    amounts: {
      for (final e in ((json['amounts'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    },
    incomePerSecond: {
      for (final e in ((json['incomePerSecond'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
    carry: {
      for (final e in ((json['carry'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
  );
}

/// A building (or any entity) that turns resources into units over time.
///
/// The unit is described by [template], a component map in the same JSON a level
/// file uses (`{'unitStats': {...}, 'realtimeStats': {...}, 'sprite': {...}}`), so
/// what a barracks makes is data, not code. The new unit is given the producer's
/// team and an adjacent free cell automatically.
class Producer {
  /// What one unit costs, paid when its production *starts*.
  final Map<String, int> cost;

  /// Seconds to make one.
  final double seconds;

  /// The produced unit's components.
  final Map<String, dynamic> template;

  /// Units waiting to be built (including the one in progress).
  int queued;

  /// Seconds spent on the unit in progress.
  double progress;

  /// Whether the unit in progress has been paid for.
  bool paid;

  /// Technologies the team must have (see `availableTech`) before this producer starts a unit.
  /// Empty means no prerequisite.
  final List<String> requires;

  Producer({
    required this.cost,
    required this.seconds,
    required this.template,
    this.queued = 0,
    this.progress = 0,
    this.paid = false,
    List<String>? requires,
  }) : requires = requires ?? const [];

  Map<String, dynamic> toJson() => {
    'cost': cost,
    'seconds': seconds,
    'template': template,
    'queued': queued,
    'progress': progress,
    'paid': paid,
    if (requires.isNotEmpty) 'requires': requires,
  };
  factory Producer.fromJson(Map<String, dynamic> json) => Producer(
    cost: {
      for (final e in ((json['cost'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    },
    seconds: (json['seconds'] as num).toDouble(),
    template: ((json['template'] as Map?) ?? const {}).cast<String, dynamic>(),
    queued: (json['queued'] as num?)?.toInt() ?? 0,
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
    paid: json['paid'] as bool? ?? false,
    requires: [
      for (final r in (json['requires'] as List? ?? const [])) r as String,
    ],
  );
}

/// A producer finished a unit.
class UnitProducedEvent {
  final EntityId producer;
  final EntityId unit;
  UnitProducedEvent(this.producer, this.unit);
}

/// A producer could not start its next unit for lack of resources. Emitted once per
/// stall (not every tick), so a UI can flash "not enough gold".
class ProductionStalledEvent {
  final EntityId producer;
  final Map<String, int> missing;
  ProductionStalledEvent(this.producer, this.missing);
}

/// The [Treasury] that belongs to [team], or null if that team has none.
Treasury? treasuryOf(World world, String team) {
  final store = world.storeOf<Treasury>();
  for (var i = 0; i < store.length; i++) {
    if (store.denseAt(i).team == team) return store.denseAt(i);
  }
  return null;
}

/// Queues [count] more units at [producer]. Returns false if it isn't a producer
/// or [count] isn't positive.
bool queueProduction(World world, EntityId producer, [int count = 1]) {
  final p = world.storeOf<Producer>().get(producer);
  if (p == null || count < 1) return false;
  p.queued += count;
  return true;
}

/// Runs income and production by `dt`.
///
/// Per tick: every [Treasury] accrues income, then each [Producer] with units
/// queued pays for the next one (waiting, with a [ProductionStalledEvent], if its
/// team can't afford it), builds for `seconds`, and spawns the unit on the nearest
/// free cell to the producer. If every nearby cell is taken the unit waits
/// finished-but-unspawned rather than overlapping something.
///
/// Deterministic: producers run in entity-id order, so competing for the same
/// resources, or the same free cell, resolves identically on every machine.
class ProductionSystem extends System {
  ProductionSystem(this.navigator);

  /// Used only to find walkable cells to spawn onto.
  final GridNavigator navigator;

  final Set<EntityId> _stalled = {};
  final Set<EntityId> _locked = {};

  @override
  String get name => 'production';

  @override
  void update(World world, double dt) {
    final treasuries = world.storeOf<Treasury>();
    for (var i = 0; i < treasuries.length; i++) {
      treasuries.denseAt(i).accrue(dt);
    }
    final producers = world.storeOf<Producer>();
    final ids = [
      for (var i = 0; i < producers.length; i++) producers.entityAt(i),
    ]..sort();
    for (final id in ids) {
      final p = producers.get(id);
      if (p != null && p.queued > 0 && !world.storeOf<Construction>().has(id))
        _work(world, id, p, dt);
    }
  }

  void _work(World world, EntityId id, Producer p, double dt) {
    final team = world.storeOf<Team>().get(id)?.id;
    if (team == null) return;
    if (!p.paid) {
      final missing = missingTech(world, team, p.requires);
      if (missing.isNotEmpty) {
        if (_locked.add(id))
          world.events.emit(ProductionLockedEvent(id, missing));
        return;
      }
      _locked.remove(id);
      final treasury = treasuryOf(world, team);
      if (treasury == null || !treasury.spend(p.cost)) {
        if (_stalled.add(id)) {
          world.events.emit(
            ProductionStalledEvent(id, {
              for (final e in p.cost.entries)
                if ((treasury?.of(e.key) ?? 0) < e.value)
                  e.key: e.value - (treasury?.of(e.key) ?? 0),
            }),
          );
        }
        return;
      }
      _stalled.remove(id);
      p.paid = true;
    }
    p.progress = math.min(p.seconds, p.progress + dt);
    if (p.progress < p.seconds - 1e-9) return;
    final unit = _spawn(world, id, p, team);
    if (unit == null) return; // no room: stay finished until a cell frees up
    p.queued--;
    p.progress = 0;
    p.paid = false;
    world.events.emit(UnitProducedEvent(id, unit));
  }

  EntityId? _spawn(World world, EntityId producer, Producer p, String team) {
    final at = world.storeOf<GridPosition>().get(producer);
    if (at == null) return null;
    final held = cellsHeldExcept(world, const []);
    final cells = formationCells(navigator, at, 1, taken: held);
    if (cells.isEmpty) return null;
    final cell = cells.single;
    final unit = world.spawn();
    world.components.applyToEntity(unit, {
      ...p.template,
      'team': {'id': team},
      'gridPosition': {'col': cell.col, 'row': cell.row},
    });
    return unit;
  }
}
