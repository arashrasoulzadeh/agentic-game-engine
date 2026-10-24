import 'dart:math';

import '../../../engine_core.dart';
import '../context.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';
import 'level_ops.dart';

/// Systems a sandbox world may run: the ones that need nothing but the world itself and behave the same each run.
final Map<String, System Function()> _systems = {
  'movement': MovementSystem.new,
  'collision': CollisionSystem.new,
  'pushable': PushableSystem.new,
  'tileAnimation': TileAnimationSystem.new,
  'tween': TweenSystem.new,
  'particles': () => ParticleSystem(random: Random(0)),
};

World _world(OpContext ctx, Map<String, Object?> a) =>
    ctx.sandbox.get(a['worldId']! as String, ctx.clock()) ??
    (throw OpError(
      ErrorCode.notFound,
      'No world "${a['worldId']}" (it may have expired).',
      hint: 'world.build makes one.',
    ));

const _worldId = Param(
  'worldId',
  ParamType.string,
  required: true,
  positional: true,
);

/// `world.*`: headless worlds held in memory. Kind `read` on purpose: they never touch files, so a read-only server
/// still allows them.
List<Operation> worldOperations() => [
  Operation(
    name: 'world.build',
    summary: 'Load a level into a headless in-memory world and return its id.',
    description:
        'Give `path` (a project level) or inline `json`. `systems` chooses what runs on each step '
        '(${_systems.keys.join(', ')}); default movement and collision. At most 4 worlds exist at once and an unused one '
        'expires after 10 minutes. Nothing is written.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    params: [
      const Param('path', ParamType.path, positional: true),
      const Param('json', ParamType.json, cliFlag: 'inline-json'),
      Param(
        'systems',
        ParamType.array,
        items: const Param.string(),
        description: 'Subset of: ${_systems.keys.join(', ')}.',
      ),
    ],
    errors: {
      ErrorCode.rateLimited: 'Too many worlds are open; discard one.',
      ErrorCode.validationFailed: 'The level does not load.',
    },
    handler: (ctx, a) {
      final names =
          (a['systems'] as List?)?.cast<String>() ??
          const ['movement', 'collision'];
      for (final n in names) {
        if (!_systems.containsKey(n)) {
          throw OpError(
            ErrorCode.invalidParams,
            'Unknown system "$n".',
            hint: 'Choose from: ${_systems.keys.join(', ')}.',
          );
        }
      }
      final doc = parseLevel(levelText(ctx, a));
      final world = World(width: 1000, height: 1000);
      registerCoreComponents(world);
      final Map<String, int> named;
      try {
        named = Level.loadInto(world, doc.toJson());
      } on Object catch (e) {
        throw OpError(
          ErrorCode.validationFailed,
          'The level does not load ($e).',
        );
      }
      for (final n in names) {
        world.addSystem(_systems[n]!());
      }
      final id = ctx.sandbox.add(world, ctx.clock());
      if (id == null) {
        throw OpError(
          ErrorCode.rateLimited,
          'Already ${ctx.sandbox.maxWorlds} worlds are open.',
          hint: 'Call world.discard on one you no longer need.',
        );
      }
      return OpOutcome.data({
        'worldId': id,
        'entities': world.entities.count,
        'systems': names,
        'named': named,
      });
    },
  ),
  Operation(
    name: 'world.step',
    summary: 'Advance a world by a number of fixed steps.',
    description:
        'Each step is `dt` seconds (default 1/60). Returns the new tick and per-component entity counts.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    params: const [
      _worldId,
      Param('ticks', ParamType.integer, min: 1, max: 100000, defaultValue: 1),
      Param('dt', ParamType.number, min: 0.0001, max: 1, defaultValue: 1 / 60),
    ],
    handler: (ctx, a) {
      final world = _world(ctx, a);
      final dt = (a['dt']! as num).toDouble();
      for (var i = 0; i < (a['ticks']! as int); i++) {
        world.step(dt);
      }
      return OpOutcome.data({
        'tick': world.tick,
        'entities': world.entities.count,
        'components': world.componentCounts(),
      });
    },
  ),
  Operation(
    name: 'world.snapshot',
    summary: 'The world as plain JSON (tick, entities and their components).',
    description: '`entities` limits the output to those entity ids.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: [
      _worldId,
      const Param(
        'entities',
        ParamType.array,
        items: Param('', ParamType.integer),
      ),
    ],
    handler: (ctx, a) {
      final json = _world(ctx, a).toJson();
      final only = (a['entities'] as List?)?.cast<int>().toSet();
      if (only != null) {
        json['entities'] = [
          for (final e in json['entities'] as List)
            if (only.contains((e as Map)['id'])) e,
        ];
      }
      return OpOutcome.data(json);
    },
  ),
  Operation(
    name: 'world.patch',
    summary: 'Change entities in a world with a snapshot-shaped patch.',
    description:
        'The same patch `World.applyPatch` takes: `{entities: [{id, components: {name: json}}]}`. Affects only the '
        'in-memory world.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    params: const [_worldId, Param('patch', ParamType.json, required: true)],
    handler: (ctx, a) {
      final world = _world(ctx, a);
      try {
        world.applyPatch((a['patch']! as Map).cast<String, dynamic>());
      } on WorldPatchException catch (e) {
        throw OpError(ErrorCode.validationFailed, e.toString());
      } on ComponentApplyException catch (e) {
        throw OpError(ErrorCode.validationFailed, e.toString());
      }
      return OpOutcome.data({
        'applied': true,
        'entities': world.entities.count,
      });
    },
  ),
  Operation(
    name: 'world.query',
    summary:
        'Entities that have a component, optionally matching field values.',
    description:
        '`where` is `{field: value}` compared for equality against the component JSON.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      _worldId,
      Param('component', ParamType.string, required: true),
      Param('where', ParamType.object),
    ],
    handler: (ctx, a) {
      final world = _world(ctx, a);
      final name = a['component']! as String;
      final where = (a['where'] as Map?) ?? const {};
      final out = <Map<String, Object?>>[];
      for (final id in world.entities.all) {
        final c = world.components.serializeEntity(id)[name];
        if (c == null) continue;
        final ok = where.entries.every((e) => (c as Map)[e.key] == e.value);
        if (ok) out.add({'id': id, 'component': c});
      }
      return OpOutcome.data(out);
    },
  ),
  Operation(
    name: 'world.discard',
    summary: 'Drop a world from memory.',
    description: 'Frees a slot; unknown ids are `not_found`.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    params: const [_worldId],
    handler: (ctx, a) {
      if (!ctx.sandbox.discard(a['worldId']! as String)) {
        throw OpError(ErrorCode.notFound, 'No world "${a['worldId']}".');
      }
      return const OpOutcome.data({'discarded': true});
    },
  ),
];
