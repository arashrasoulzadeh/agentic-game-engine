import 'dart:convert';

import '../../../engine_core.dart';
import '../../idle/advisor.dart';
import '../../idle/components.dart';
import '../../idle/definition.dart';
import '../../idle/economy.dart';
import '../../idle/simulator.dart';
import '../context.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';

Map<String, dynamic> _definition(OpContext ctx, Map<String, Object?> a) {
  final inline = a['json'];
  if (inline is Map) return inline.cast<String, dynamic>();
  final rel = a['path'] as String?;
  if (rel == null)
    throw OpError(
      ErrorCode.invalidParams,
      'Give "path" (a project file) or "json" (inline definition).',
    );
  if (ctx.project == null)
    throw OpError(
      ErrorCode.notFound,
      'No project is open.',
      hint: 'Call project.open first.',
    );
  final text = ctx.files.read(ctx.project!.resolve(rel));
  if (text == null) throw OpError(ErrorCode.notFound, 'No file at $rel.');
  try {
    return (jsonDecode(text) as Map).cast<String, dynamic>();
  } on Object catch (e) {
    throw OpError(
      ErrorCode.validationFailed,
      '$rel is not a JSON object ($e).',
    );
  }
}

/// `idle.*`: the idle-game tools over a definition JSON.
List<Operation> idleOperations() => [
  Operation(
    name: 'idle.validate',
    summary:
        'Check an idle game definition and list every problem with its path.',
    description:
        'Give `path` (a project file such as assets/idle_game.json) or inline `json`. Nothing is run or written.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('path', ParamType.path, positional: true),
      Param(
        'json',
        ParamType.json,
        cliFlag: 'inline-json',
        description: 'The definition, instead of a file.',
      ),
    ],
    handler: (ctx, a) {
      final json = _definition(ctx, a);
      final problems = validateIdleDefinition(json);
      return OpOutcome.data({
        'ok': problems.isEmpty,
        'problems': problems,
        'generators': (json['generators'] as List?)?.length ?? 0,
        'upgrades': (json['upgrades'] as List?)?.length ?? 0,
      });
    },
    examples: const [
      Example(
        'Minimal',
        {
          'json': {'generators': []},
        },
        expect: {'ok': true},
      ),
    ],
  ),
  Operation(
    name: 'idle.simulate',
    summary:
        'Play an idle game with a deterministic greedy strategy and report its pacing.',
    description:
        'Always buys the best-payback purchase, waiting just long enough to afford it, and prestiges when it would '
        'give `prestigeAt` times what is held. Same input, same report. Use it to tune cost curves without playing.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('path', ParamType.path, positional: true),
      Param('json', ParamType.json, cliFlag: 'inline-json'),
      Param('days', ParamType.number, min: 0.01, max: 3650, defaultValue: 3),
      Param(
        'prestigeAt',
        ParamType.number,
        min: 0.01,
        description: 'Prestige once the gain is this many times what is held.',
      ),
      Param('mainResource', ParamType.string, defaultValue: 'coins'),
    ],
    errors: {
      ErrorCode.validationFailed:
          'The definition has problems (details.problems).',
    },
    handler: (ctx, a) {
      final json = _definition(ctx, a);
      final problems = validateIdleDefinition(json);
      if (problems.isNotEmpty) {
        throw OpError(
          ErrorCode.validationFailed,
          'The definition has ${problems.length} problem(s).',
          details: {'problems': problems},
        );
      }
      final world = World(width: 10, height: 10);
      registerCoreComponents(world);
      final game = loadIdleDefinition(world, json);
      final report = simulateIdle(
        world,
        game.wallet,
        limit: Duration(hours: ((a['days']! as num) * 24).round()),
        prestigeAt: (a['prestigeAt'] as num?)?.toDouble(),
        mainResource: a['mainResource']! as String,
      );
      return OpOutcome.data({
        'elapsedSeconds': report.elapsed.inSeconds,
        'purchases': report.purchases,
        'stalled': report.stalled,
        if (report.stallReason != null) 'stallReason': report.stallReason,
        'milestones': [
          for (final m in report.milestones)
            {'atSeconds': m.at.inSeconds, 'label': m.label},
        ],
        'finalIncome': {
          for (final e in report.finalIncome.entries)
            e.key: formatBigNumber(e.value),
        },
        'text': describeSimulation(report),
      });
    },
    examples: const [
      Example('One day', {
        'json': {
          'resources': {
            'coins': {'start': '15'},
          },
          'generators': [
            {
              'id': 'cursor',
              'cost': {'type': 'geometric', 'base': '15', 'growth': 1.15},
              'output': {'coins': '0.5'},
            },
          ],
        },
        'days': 1,
      }),
    ],
  ),
  Operation(
    name: 'idle.format_number',
    summary:
        'Write a big number the way the game shows it (1.5M, 1.5e6, 1,500,000).',
    description:
        'Values are strings like "1.5e300" because they do not fit a double.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('value', ParamType.string, required: true, positional: true),
      Param(
        'style',
        ParamType.enumeration,
        options: ['suffix', 'scientific', 'engineering', 'grouped'],
        defaultValue: 'suffix',
      ),
      Param('decimals', ParamType.integer, min: 0, max: 10, defaultValue: 2),
    ],
    handler: (ctx, a) {
      final BigNumber n;
      try {
        n = BigNumber.parse(a['value']! as String);
      } on Object {
        throw OpError(
          ErrorCode.invalidParams,
          '"${a['value']}" is not a number.',
        );
      }
      final style = NumberStyle.values.firstWhere((s) => s.name == a['style']);
      return OpOutcome.data({
        'text': formatBigNumber(
          n,
          style: style,
          decimals: a['decimals']! as int,
        ),
      });
    },
    examples: const [
      Example('Millions', {'value': '1234567'}, expect: {'text': '1.23M'}),
    ],
  ),
  Operation(
    name: 'idle.best_purchase',
    summary:
        'The purchase the greedy advisor would make next, with its cost and income gain.',
    description:
        'Loads the definition at its starting state (optionally with `owned` counts applied to generators) and asks the '
        'same advisor the auto-buyer and balance simulator use. `null` data means nothing adds income.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('path', ParamType.path, positional: true),
      Param('json', ParamType.json, cliFlag: 'inline-json'),
      Param(
        'owned',
        ParamType.object,
        description: 'Generator id -> copies already owned.',
      ),
      Param('mainResource', ParamType.string, defaultValue: 'coins'),
    ],
    errors: {
      ErrorCode.validationFailed:
          'The definition has problems (details.problems).',
    },
    handler: (ctx, a) {
      final json = _definition(ctx, a);
      final problems = validateIdleDefinition(json);
      if (problems.isNotEmpty) {
        throw OpError(
          ErrorCode.validationFailed,
          'The definition has ${problems.length} problem(s).',
          details: {'problems': problems},
        );
      }
      final world = World(width: 10, height: 10);
      registerCoreComponents(world);
      final game = loadIdleDefinition(world, json);
      final owned = (a['owned'] as Map?) ?? const {};
      final gens = world.storeOf<Generator>();
      for (var i = 0; i < gens.length; i++) {
        final g = gens.denseAt(i);
        final n = owned[g.id];
        if (n is int) g.owned = n;
      }
      recomputeIncome(world, game.wallet);
      final best = bestPurchase(
        world,
        game.wallet,
        mainResource: a['mainResource']! as String,
      );
      if (best == null) return const OpOutcome.data(null);
      final gen = gens.get(best.entity);
      return OpOutcome.data({
        'id': gen?.id ?? best.entity.toString(),
        'isUpgrade': best.isUpgrade,
        'resource': best.resource,
        'cost': formatBigNumber(best.cost),
        'gain': formatBigNumber(best.gain),
        'payback': formatBigNumber(best.payback),
      });
    },
  ),
];
