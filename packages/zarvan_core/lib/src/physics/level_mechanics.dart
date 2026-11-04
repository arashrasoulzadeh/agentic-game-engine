import 'package:zarvan_schema/zarvan_schema.dart'
    show conveyorZoneSchema, teleporterSchema;

import '../ecs/entity.dart';
import '../ecs/system.dart';
import '../ecs/world.dart';
import 'position.dart';
import 'tile_map.dart';
import 'velocity.dart';

/// A rectangle (centred on the carrying entity's `Position`) that drags every
/// other body with a `Velocity` inside it along at ([speedX], [speedY]) units
/// per second: a conveyor belt, a current, a wind tunnel.
///
/// Tile conveyors (`TileMap.conveyorSpeedByTileId`) only exist on the grid;
/// this is the free-placed, any-direction version a level author drops as an
/// entity. Moves `Position` directly (not `Velocity`), so it never fights a
/// body's own movement logic.
class ConveyorZone {
  ConveyorZone({
    this.width = 64,
    this.height = 16,
    this.speedX = 60,
    this.speedY = 0,
  });

  double width;
  double height;
  double speedX;
  double speedY;

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'speedX': speedX,
    'speedY': speedY,
  };

  factory ConveyorZone.fromJson(Map<String, dynamic> json) => ConveyorZone(
    width: (json['width'] as num?)?.toDouble() ?? 64,
    height: (json['height'] as num?)?.toDouble() ?? 16,
    speedX: (json['speedX'] as num?)?.toDouble() ?? 60,
    speedY: (json['speedY'] as num?)?.toDouble() ?? 0,
  );
}

/// A rectangle (centred on its `Position`) that moves any body with a
/// `Velocity` entering it to ([targetX], [targetY]), or to another entity's
/// position when [targetEntity] is set. A per-body [cooldown] (seconds) stops
/// a pair of linked teleporters bouncing the body back and forth.
class Teleporter {
  Teleporter({
    this.width = 32,
    this.height = 32,
    this.targetX = 0,
    this.targetY = 0,
    this.targetEntity,
    this.cooldown = 0.5,
  });

  double width;
  double height;
  double targetX;
  double targetY;

  /// If set and alive, the destination is that entity's position instead.
  EntityId? targetEntity;

  /// Seconds before the same body can be teleported again by any teleporter.
  double cooldown;

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'targetX': targetX,
    'targetY': targetY,
    'targetEntity': targetEntity,
    'cooldown': cooldown,
  };

  factory Teleporter.fromJson(Map<String, dynamic> json) => Teleporter(
    width: (json['width'] as num?)?.toDouble() ?? 32,
    height: (json['height'] as num?)?.toDouble() ?? 32,
    targetX: (json['targetX'] as num?)?.toDouble() ?? 0,
    targetY: (json['targetY'] as num?)?.toDouble() ?? 0,
    targetEntity: json['targetEntity'] as int?,
    cooldown: (json['cooldown'] as num?)?.toDouble() ?? 0.5,
  );
}

/// Emitted when a [Teleporter] moves a body.
class Teleported {
  Teleported({required this.entity, required this.teleporter});

  final EntityId entity;
  final EntityId teleporter;
}

bool _inside(Position c, double w, double h, Position p) =>
    (p.x - c.x).abs() <= w / 2 && (p.y - c.y).abs() <= h / 2;

/// Applies every [ConveyorZone]. Register it before `MovementSystem` /
/// collision so the drift is resolved against walls in the same step.
class ConveyorZoneSystem extends System {
  @override
  String get name => 'conveyor-zone';

  @override
  void update(World world, double dt) {
    final zones = world.componentsOf<ConveyorZone>();
    if (zones.length == 0 || dt <= 0) return;
    final positions = world.componentsOf<Position>();
    final velocities = world.componentsOf<Velocity>();
    for (var i = 0; i < zones.length; i++) {
      final zid = zones.entityAt(i);
      final z = zones.denseAt(i);
      final c = positions.get(zid);
      if (c == null) continue;
      for (var k = 0; k < velocities.length; k++) {
        final id = velocities.entityAt(k);
        if (id == zid) continue;
        final p = positions.get(id);
        if (p == null || !_inside(c, z.width, z.height, p)) continue;
        p.x += z.speedX * dt;
        p.y += z.speedY * dt;
      }
    }
  }
}

/// Applies every [Teleporter]; emits [Teleported].
class TeleporterSystem extends System {
  final Map<EntityId, double> _cooling = {};

  @override
  String get name => 'teleporter';

  @override
  void update(World world, double dt) {
    final tele = world.componentsOf<Teleporter>();
    _cooling.removeWhere((_, left) => left - dt <= 0);
    for (final k in _cooling.keys.toList()) {
      _cooling[k] = _cooling[k]! - dt;
    }
    if (tele.length == 0) return;
    final positions = world.componentsOf<Position>();
    final velocities = world.componentsOf<Velocity>();
    for (var i = 0; i < tele.length; i++) {
      final tid = tele.entityAt(i);
      final t = tele.denseAt(i);
      final c = positions.get(tid);
      if (c == null) continue;
      var tx = t.targetX;
      var ty = t.targetY;
      final to = t.targetEntity;
      if (to != null) {
        final dest = positions.get(to);
        if (dest == null) continue;
        tx = dest.x;
        ty = dest.y;
      }
      for (var k = 0; k < velocities.length; k++) {
        final id = velocities.entityAt(k);
        if (id == tid || _cooling.containsKey(id)) continue;
        final p = positions.get(id);
        if (p == null || !_inside(c, t.width, t.height, p)) continue;
        p.x = tx;
        p.y = ty;
        if (t.cooldown > 0) _cooling[id] = t.cooldown;
        world.events.emit(Teleported(entity: id, teleporter: tid));
      }
    }
  }
}

/// How a tile id breaks: after [hits] strikes it becomes [becomes] (0 = air).
class DestructibleTile {
  const DestructibleTile({this.hits = 1, this.becomes = 0});

  final int hits;
  final int becomes;
}

/// Tracks damage to breakable tiles of a [TileMap] and swaps them out.
///
/// Call [hit] from whatever strikes the tile (an explosion, a pickaxe, a
/// stomp). Damage is kept per cell here, not in the map, so the map's saved
/// JSON stays the plain grid and a reload starts with fresh tiles' health.
class DestructibleTiles {
  DestructibleTiles(this.map, this.specs);

  final TileMap map;

  /// Breakable tile ids and how they break.
  final Map<int, DestructibleTile> specs;

  final Map<int, int> _damage = {};

  /// Strikes the tile at ([col], [row]). Returns true if it broke (and was
  /// replaced); false if it survived or is not breakable.
  bool hit(int col, int row, {int power = 1}) {
    if (col < 0 || row < 0 || col >= map.cols || row >= map.rows) return false;
    final spec = specs[map.tileAt(col, row)];
    if (spec == null) return false;
    final key = row * map.cols + col;
    final dmg = (_damage[key] ?? 0) + power;
    if (dmg < spec.hits) {
      _damage[key] = dmg;
      return false;
    }
    _damage.remove(key);
    map.tiles[key] = spec.becomes;
    return true;
  }

  /// Hits every breakable tile whose cell centre is within [radius] of
  /// ([x], [y]) (an explosion). Returns the number that broke.
  int blast(double x, double y, double radius, {int power = 1}) {
    var broken = 0;
    final c0 = map.colAtX(x - radius), c1 = map.colAtX(x + radius);
    final r0 = map.rowAtY(y - radius), r1 = map.rowAtY(y + radius);
    for (var r = r0; r <= r1; r++) {
      for (var c = c0; c <= c1; c++) {
        final dx = (c + 0.5) * map.tileWidth - x;
        final dy = (r + 0.5) * map.tileHeight - y;
        if (dx * dx + dy * dy > radius * radius) continue;
        if (hit(c, r, power: power)) broken++;
      }
    }
    return broken;
  }
}

/// Registers [ConveyorZone] and [Teleporter] for serialization and the studio.
void registerLevelMechanicsComponents(World world) {
  if (!world.components.isRegistered('conveyorZone')) {
    world.components.register<ConveyorZone>(
      'conveyorZone',
      (c) => c.toJson(),
      ConveyorZone.fromJson,
      schema: conveyorZoneSchema,
    );
  }
  if (!world.components.isRegistered('teleporter')) {
    world.components.register<Teleporter>(
      'teleporter',
      (c) => c.toJson(),
      Teleporter.fromJson,
      schema: teleporterSchema,
    );
  }
}
