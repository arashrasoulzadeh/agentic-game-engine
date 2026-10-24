import '../../content/save_codec.dart';
import '../operation.dart';
import '../param.dart';
import '../result.dart';

OpError _bad(SaveFormatException e) =>
    OpError(ErrorCode.validationFailed, e.message);

/// `save.*`: the shareable save text and version migration, over inline JSON (no project needed).
List<Operation> saveOperations() => [
  Operation(
    name: 'save.encode',
    summary:
        'Turn a save into the shareable text a player can copy (GSAVE1...).',
    description:
        'The text carries the JSON in URL-safe base64 plus a checksum, so a typo is caught when it is imported.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [Param('save', ParamType.object, required: true)],
    examples: const [
      Example('Encode a save', {
        'save': {'coins': '42'},
      }),
    ],
    handler: (ctx, a) => OpOutcome.data({
      'code': SaveCodec.export((a['save']! as Map).cast<String, dynamic>()),
    }),
  ),
  Operation(
    name: 'save.decode',
    summary: 'Read a save text back into its JSON.',
    description:
        'Fails with `validation_failed` and a player-readable message when the text is damaged or not a save code.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('code', ParamType.string, required: true, positional: true),
    ],
    errors: {ErrorCode.validationFailed: 'The text is not a valid save code.'},
    handler: (ctx, a) {
      try {
        return OpOutcome.data({'save': SaveCodec.import(a['code']! as String)});
      } on SaveFormatException catch (e) {
        throw _bad(e);
      }
    },
  ),
  Operation(
    name: 'save.migrate',
    summary: 'Check that a save can be upgraded to a version, and stamp it.',
    description:
        'Runs the registered migrations from the save\'s `saveVersion` (1 when absent) up to `toVersion`. The engine ships '
        'no migrations of its own, so this reports `validation_failed` for any gap and succeeds only for a save already at '
        '`toVersion`; games register theirs with `SaveMigrator`.',
    kind: OperationKind.read,
    scope: OperationScope.pure,
    idempotent: true,
    params: const [
      Param('save', ParamType.object, required: true),
      Param('toVersion', ParamType.integer, required: true, min: 1),
    ],
    handler: (ctx, a) {
      try {
        return OpOutcome.data({
          'save': SaveMigrator(
            currentVersion: a['toVersion']! as int,
          ).migrate((a['save']! as Map).cast<String, dynamic>()),
        });
      } on SaveFormatException catch (e) {
        throw _bad(e);
      }
    },
  ),
];
