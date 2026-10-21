import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'economy.dart';
import 'formation.dart';
import 'grid_navigation.dart';
import 'order.dart';
import 'turn_components.dart';

/// A deposit units can harvest: a tree, a gold mine. It sits on a cell (give the entity a
/// `GridPosition`) and runs out; when the last unit is taken the node is destroyed.
class ResourceNode {
  /// The resource name a harvester ends up carrying, e.g. `gold`.
  final String resource;

  /// Units left to harvest.
  int amount;

  ResourceNode(this.resource, this.amount);

  Map<String, dynamic> toJson() => {'resource': resource, 'amount': amount};
  factory ResourceNode.fromJson(Map<String, dynamic> json) =>
      ResourceNode(json['resource'] as String, (json['amount'] as num).toInt());
}

/// Marks a team building where [Gatherer]s hand in what they carry (a town hall, a
/// storehouse). The delivery goes to that team's [Treasury].
class Depot {
  /// Resource names this depot takes; empty means any.
  final Set<String> accepts;

  Depot({Set<String>? accepts}) : accepts = accepts ?? {};

  bool take(String resource) => accepts.isEmpty || accepts.contains(resource);

  Map<String, dynamic> toJson() => {'accepts': accepts.toList()..sort()};
  factory Depot.fromJson(Map<String, dynamic> json) => Depot(
    accepts: {
      for (final a in (json['accepts'] as List? ?? const [])) a as String,
    },
  );
}

/// Where a [Gatherer] is in its loop.
enum GatherPhase { idle, toNode, harvesting, toDepot }

/// A unit that harvests a [ResourceNode] and carries the haul to a [Depot], then goes back
/// for more until the node is gone. Give it to a unit that also has `RealtimeStats` and an
/// `OrderQueue` (the system moves it by queueing `MoveOrder`s) and start it with
/// [assignGather].
class Gatherer {
  /// Most units it carries before heading home.
  final int capacity;

  /// Seconds to harvest one unit.
  final double secondsPerUnit;

  /// The node it is working, or null when idle.
  EntityId? node;
  GatherPhase phase;

  /// What it carries now (null when empty) and how much.
  String? carrying;
  int carried;

  /// Seconds into harvesting the next unit. Serialized, so a saved game resumes mid-swing.
  double progress;

  Gatherer({
    this.capacity = 10,
    this.secondsPerUnit = 1,
    this.node,
    this.phase = GatherPhase.idle,
    this.carrying,
    this.carried = 0,
    this.progress = 0,
  });

  Map<String, dynamic> toJson() => {
    'capacity': capacity,
    'secondsPerUnit': secondsPerUnit,
    'node': node,
    'phase': phase.name,
    'carrying': carrying,
    'carried': carried,
    'progress': progress,
  };
  factory Gatherer.fromJson(Map<String, dynamic> json) => Gatherer(
    capacity: (json['capacity'] as num?)?.toInt() ?? 10,
    secondsPerUnit: (json['secondsPerUnit'] as num?)?.toDouble() ?? 1,
    node: (json['node'] as num?)?.toInt(),
    phase: GatherPhase.values.firstWhere(
      (p) => p.name == json['phase'],
      orElse: () => GatherPhase.idle,
    ),
    carrying: json['carrying'] as String?,
    carried: (json['carried'] as num?)?.toInt() ?? 0,
    progress: (json['progress'] as num?)?.toDouble() ?? 0,
  );
}

/// A gatherer handed in what it carried.
class ResourceDeliveredEvent {
  final EntityId unit;
  final String team;
  final String resource;
  final int amount;
  ResourceDeliveredEvent(this.unit, this.team, this.resource, this.amount);
}

/// A node's last unit was taken and the node was removed.
class ResourceDepletedEvent {
  final EntityId node;
  ResourceDepletedEvent(this.node);
}

/// Sends [unit] to harvest [node]. Returns false (and changes nothing) when the unit is not
/// a [Gatherer], or the node is gone or empty. A unit already carrying a different resource
/// drops it: carrying two kinds is not modelled.
bool assignGather(World world, EntityId unit, EntityId node) {
  final g = world.storeOf<Gatherer>().get(unit);
  final n = world.storeOf<ResourceNode>().get(node);
  if (g == null || n == null || n.amount <= 0) return false;
  if (g.carrying != null && g.carrying != n.resource) {
    g.carrying = null;
    g.carried = 0;
  }
  g.node = node;
  g.phase = GatherPhase.toNode;
  g.progress = 0;
  world.storeOf<OrderQueue>().get(unit)?.orders.clear();
  return true;
}

/// Runs every [Gatherer]'s harvest-and-haul loop: walk to the node, harvest, walk to the
/// nearest depot of its team, deliver into the team [Treasury], repeat.
///
/// Deterministic: gatherers are processed by entity id, and the nearest depot breaks ties by
/// id. Put it **before** `RealtimeOrderSystem` so the move it queues starts the same step.
class GatherSystem extends System {
  GatherSystem(this.navigator);

  final GridNavigator navigator;

  @override
  String get name => 'gather';

  @override
  void update(World world, double dt) {
    final gatherers = world.storeOf<Gatherer>();
    final ids = [
      for (var i = 0; i < gatherers.length; i++) gatherers.entityAt(i),
    ]..sort();
    for (final id in ids) {
      final g = gatherers.get(id);
      if (g == null || !world.entities.isAlive(id)) continue;
      switch (g.phase) {
        case GatherPhase.idle:
          break;
        case GatherPhase.toNode:
          _toNode(world, id, g);
        case GatherPhase.harvesting:
          _harvest(world, id, g, dt);
        case GatherPhase.toDepot:
          _toDepot(world, id, g);
      }
    }
  }

  ResourceNode? _liveNode(World world, Gatherer g) {
    final id = g.node;
    if (id == null || !world.entities.isAlive(id)) return null;
    final n = world.storeOf<ResourceNode>().get(id);
    return n == null || n.amount <= 0 ? null : n;
  }

  void _toNode(World world, EntityId id, Gatherer g) {
    if (_liveNode(world, g) == null) {
      g.node = null;
      g.phase = g.carried > 0 ? GatherPhase.toDepot : GatherPhase.idle;
      return;
    }
    final here = world.storeOf<GridPosition>().get(id);
    final there = world.storeOf<GridPosition>().get(g.node!);
    if (here == null || there == null) return;
    if (here.chebyshev(there) <= 1) {
      g.phase = GatherPhase.harvesting;
      g.progress = 0;
      world.storeOf<OrderQueue>().get(id)?.orders.clear();
      return;
    }
    _walkNextTo(world, id, there);
  }

  void _harvest(World world, EntityId id, Gatherer g, double dt) {
    final node = _liveNode(world, g);
    if (node != null) {
      g.progress += dt;
      while (g.progress >= g.secondsPerUnit - 1e-9 &&
          g.carried < g.capacity &&
          node.amount > 0) {
        g.progress -= g.secondsPerUnit;
        node.amount--;
        g.carrying = node.resource;
        g.carried++;
      }
      if (node.amount <= 0) {
        world.events.emit(ResourceDepletedEvent(g.node!));
        world.destroy(g.node!);
        g.node = null;
      }
    }
    final full = g.carried >= g.capacity;
    if (full || g.node == null) {
      g.progress = 0;
      g.phase = g.carried > 0 ? GatherPhase.toDepot : GatherPhase.idle;
    }
  }

  void _toDepot(World world, EntityId id, Gatherer g) {
    final team = world.storeOf<Team>().get(id)?.id;
    final here = world.storeOf<GridPosition>().get(id);
    final resource = g.carrying;
    if (team == null || here == null || resource == null || g.carried <= 0) {
      g.phase = GatherPhase.idle;
      return;
    }
    final depot = _nearestDepot(world, team, resource, here);
    if (depot == null) return; // nowhere to deliver yet: wait, keeping the haul
    final there = world.storeOf<GridPosition>().get(depot)!;
    if (here.chebyshev(there) > 1) {
      _walkNextTo(world, id, there);
      return;
    }
    treasuryOf(world, team)?.add(resource, g.carried);
    world.events.emit(ResourceDeliveredEvent(id, team, resource, g.carried));
    g.carried = 0;
    g.carrying = null;
    g.progress = 0;
    g.phase = _liveNode(world, g) == null
        ? GatherPhase.idle
        : GatherPhase.toNode;
  }

  EntityId? _nearestDepot(
    World world,
    String team,
    String resource,
    GridPosition from,
  ) {
    final depots = world.storeOf<Depot>();
    final teams = world.storeOf<Team>();
    final grid = world.storeOf<GridPosition>();
    final building = world.storeOf<Construction>();
    EntityId? best;
    var bestD = 1 << 30;
    for (var i = 0; i < depots.length; i++) {
      final d = depots.entityAt(i);
      if (!depots.denseAt(i).take(resource) ||
          teams.get(d)?.id != team ||
          building.has(d))
        continue;
      final p = grid.get(d);
      if (p == null) continue;
      final dist = from.chebyshev(p);
      if (dist < bestD || (dist == bestD && d < best!)) {
        bestD = dist;
        best = d;
      }
    }
    return best;
  }

  /// Queues a move to the nearest free cell touching [target], unless it is already moving.
  void _walkNextTo(World world, EntityId id, GridPosition target) {
    final queue = world.storeOf<OrderQueue>().get(id);
    if (queue == null || queue.orders.isNotEmpty) return;
    final cells = formationCells(
      navigator,
      target,
      8,
      taken: cellsHeldExcept(world, [id]),
    ).where((c) => c.chebyshev(target) <= 1);
    if (cells.isEmpty) return;
    final here = world.storeOf<GridPosition>().get(id)!;
    final cell = cells.reduce(
      (a, b) => a.chebyshev(here) <= b.chebyshev(here) ? a : b,
    );
    queue.orders.add(MoveOrder(cell.col, cell.row));
  }
}
