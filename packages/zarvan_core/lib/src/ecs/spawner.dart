import 'dart:math' as math;

import 'package:zarvan_schema/zarvan_schema.dart'
    show spawnedBySchema, spawnerSchema;

import '../content/prefab_registry.dart';
import '../physics/position.dart';
import 'entity.dart';
import 'system.dart';
import 'world.dart';

/// One timed burst of a [Spawner]: [count] spawns once the spawner has run for
/// [at] seconds.
class SpawnWave {
  const SpawnWave({required this.at, this.count = 1});

  final double at;
  final int count;

  Map<String, dynamic> toJson() => {'at': at, 'count': count};

  factory SpawnWave.fromJson(Map<String, dynamic> json) => SpawnWave(
    at: (json['at'] as num).toDouble(),
    count: (json['count'] as num?)?.toInt() ?? 1,
  );
}

/// Spawns a prefab on a schedule, as data: put it on an entity with a
/// `Position` and a [SpawnerSystem] in the world. Works for any genre: a
/// trickle of coins, enemy waves, a bullet hell emitter.
///
/// Either spawn every [every] seconds (the first at [delay], so with no delay
/// it spawns at once), or at the times in
/// [waves]; [maxAlive] caps how many of its spawns may exist at once and
/// [total] stops it for good after that many (0 = no limit).
class Spawner {
  Spawner({
    required this.prefab,
    this.every = 1,
    this.count = 1,
    this.maxAlive = 0,
    this.total = 0,
    this.delay = 0,
    this.radius = 0,
    this.active = true,
    List<SpawnWave>? waves,
    this.elapsed = 0,
    this.spawned = 0,
    this.cycles = 0,
    this.waveIndex = 0,
  }) : waves = waves ?? [];

  /// Name of the prefab in the `PrefabRegistry`.
  String prefab;

  /// Seconds between spawns, and how many spawn each time (ignored when
  /// [waves] is not empty).
  double every;
  int count;

  /// Most live spawns at once (0 = unlimited) and spawns before it retires
  /// (0 = never).
  int maxAlive;
  int total;

  /// Seconds before the first periodic spawn.
  double delay;

  /// Spawns land at a random point within this radius of the spawner.
  double radius;

  /// Off stops the clock too, so it resumes where it left off.
  bool active;

  /// When not empty, spawns happen at these times instead of every [every].
  final List<SpawnWave> waves;

  /// Runtime state, saved so a loaded game resumes mid-schedule: seconds run,
  /// spawns made, periodic spawns done, next wave.
  double elapsed;
  int spawned;
  int cycles;
  int waveIndex;

  /// Whether the spawner has spawned all it ever will.
  bool get retired => total > 0 && spawned >= total;

  Map<String, dynamic> toJson() => {
    'prefab': prefab,
    'every': every,
    'count': count,
    'maxAlive': maxAlive,
    'total': total,
    'delay': delay,
    'radius': radius,
    'active': active,
    'waves': [for (final w in waves) w.toJson()],
    'elapsed': elapsed,
    'spawned': spawned,
    'cycles': cycles,
    'waveIndex': waveIndex,
  };

  factory Spawner.fromJson(Map<String, dynamic> json) => Spawner(
    prefab: json['prefab'] as String,
    every: (json['every'] as num?)?.toDouble() ?? 1,
    count: (json['count'] as num?)?.toInt() ?? 1,
    maxAlive: (json['maxAlive'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    delay: (json['delay'] as num?)?.toDouble() ?? 0,
    radius: (json['radius'] as num?)?.toDouble() ?? 0,
    active: json['active'] as bool? ?? true,
    waves: [
      for (final w in (json['waves'] as List?) ?? const [])
        SpawnWave.fromJson((w as Map).cast<String, dynamic>()),
    ],
    elapsed: (json['elapsed'] as num?)?.toDouble() ?? 0,
    spawned: (json['spawned'] as num?)?.toInt() ?? 0,
    cycles: (json['cycles'] as num?)?.toInt() ?? 0,
    waveIndex: (json['waveIndex'] as num?)?.toInt() ?? 0,
  );
}

/// Marks an entity as spawned by [spawner], so the spawner can count what is
/// still alive. Removed with the entity.
class SpawnedBy {
  SpawnedBy(this.spawner);

  final EntityId spawner;

  Map<String, dynamic> toJson() => {'spawner': spawner};

  factory SpawnedBy.fromJson(Map<String, dynamic> json) =>
      SpawnedBy(json['spawner'] as int);
}

/// Emitted for each prefab a [Spawner] spawns.
class Spawned {
  Spawned({required this.spawner, required this.entity, required this.prefab});

  final EntityId spawner;
  final EntityId entity;
  final String prefab;
}

/// Runs every [Spawner]: counts down its schedule and spawns from [registry].
class SpawnerSystem extends System {
  SpawnerSystem(this.registry);

  final PrefabRegistry registry;

  /// Tolerance for floating-point drift in accumulated `dt`, so a spawn due at
  /// exactly 5.0 s is not missed because the clock read 4.999999999999999.
  static const _eps = 1e-9;

  @override
  String get name => 'spawner';

  @override
  void update(World world, double dt) {
    final spawners = world.componentsOf<Spawner>();
    if (spawners.length == 0) return;
    final alive = <EntityId, int>{};
    final spawnedBy = world.componentsOf<SpawnedBy>();
    for (var i = 0; i < spawnedBy.length; i++) {
      final owner = spawnedBy.denseAt(i).spawner;
      alive[owner] = (alive[owner] ?? 0) + 1;
    }
    for (var i = 0; i < spawners.length; i++) {
      final id = spawners.entityAt(i);
      final s = spawners.denseAt(i);
      final at = world.componentsOf<Position>().get(id);
      if (!s.active || s.retired || at == null) continue;
      s.elapsed += dt;
      var live = alive[id] ?? 0;
      int room() => s.maxAlive == 0 ? 1 << 30 : s.maxAlive - live;
      int left() => s.total == 0 ? 1 << 30 : s.total - s.spawned;

      void spawn(int n) {
        for (var k = 0; k < n && room() > 0 && left() > 0; k++) {
          final angle = world.random.nextDouble() * 2 * math.pi;
          final dist = s.radius * math.sqrt(world.random.nextDouble());
          final instance = registry.spawn(
            world,
            s.prefab,
            at.x + math.cos(angle) * dist,
            at.y + math.sin(angle) * dist,
          );
          world.componentsOf<SpawnedBy>().set(instance.root, SpawnedBy(id));
          s.spawned++;
          live++;
          world.events.emit(
            Spawned(spawner: id, entity: instance.root, prefab: s.prefab),
          );
        }
      }

      if (s.waves.isNotEmpty) {
        while (s.waveIndex < s.waves.length &&
            s.elapsed + _eps >= s.waves[s.waveIndex].at) {
          spawn(s.waves[s.waveIndex].count);
          s.waveIndex++;
        }
      } else if (s.every > 0) {
        while (s.elapsed + _eps >= s.delay + s.every * s.cycles && !s.retired) {
          if (room() <= 0) {
            // Blocked by the cap: wait here rather than banking spawns to
            // release in a burst once there is room.
            s.elapsed = s.delay + s.every * s.cycles;
            break;
          }
          spawn(s.count);
          s.cycles++;
        }
      }
    }
  }
}

/// Registers [Spawner] and [SpawnedBy] so they serialize.
void registerSpawnerComponents(World world) {
  if (world.components.isRegistered('spawner')) return;
  world.components.register<Spawner>(
    'spawner',
    (s) => s.toJson(),
    Spawner.fromJson,
    schema: spawnerSchema,
  );
  world.components.register<SpawnedBy>(
    'spawnedBy',
    (s) => s.toJson(),
    SpawnedBy.fromJson,
    schema: spawnedBySchema,
  );
}
