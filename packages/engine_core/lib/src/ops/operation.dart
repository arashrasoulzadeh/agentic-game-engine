import 'dart:async';

import 'context.dart';
import 'param.dart';
import 'result.dart';

/// Whether an operation only reads, changes files, or changes files in a way that deserves a preview first.
enum OperationKind { read, write, destructive }

/// Whether an operation needs an open project or works on its own arguments.
enum OperationScope { pure, project }

typedef OpHandler =
    FutureOr<OpOutcome> Function(OpContext ctx, Map<String, Object?> args);

/// A documented call that is executed by the registry tests against a scratch project, so examples cannot rot.
class Example {
  const Example(this.title, this.args, {this.expect});

  final String title;
  final Map<String, Object?> args;

  /// Entries the result `data` must contain (subset match).
  final Map<String, Object?>? expect;
}

class Deprecation {
  const Deprecation({
    required this.since,
    required this.removeIn,
    this.replacement,
  });

  final String since;
  final String removeIn;
  final String? replacement;
}

/// How an operation appears as a `game_agent` command.
class CliHints {
  const CliHints({this.group, this.verb, this.legacy = const []});

  /// Overrides the command group (default: the operation's group).
  final String? group;

  /// Overrides the command name (default: the verb with underscores as hyphens).
  final String? verb;

  /// Old command paths that keep working, such as `studio add-entity`.
  final List<String> legacy;
}

/// One named, typed, documented function of the engine, available on every surface (CLI, MCP, REST, JSON-RPC).
///
/// Names are `group.verb` in lower snake case. A handler never writes files itself: it returns an [OpOutcome]
/// with a [Proposal] and the safety pipeline previews, confirms, applies and records it.
class Operation {
  const Operation({
    required this.name,
    required this.summary,
    required this.description,
    required this.kind,
    required this.scope,
    required this.handler,
    this.params = const [],
    this.result = const ResultSpec.any(),
    this.errors = const {},
    this.examples = const [],
    this.requiresFlutter = false,
    this.idempotent = false,
    this.since = '0.1.0',
    this.deprecated,
    this.cli = const CliHints(),
  });

  static final namePattern = RegExp(r'^[a-z][a-z0-9]*\.[a-z][a-z0-9_]*$');

  final String name;

  /// At most 100 characters, imperative; shown in lists.
  final String summary;

  /// Markdown: what it does, when to use it, side effects, pitfalls.
  final String description;
  final OperationKind kind;
  final OperationScope scope;
  final OpHandler handler;
  final List<Param> params;
  final ResultSpec result;

  /// Error codes this operation can return, each with a sentence.
  final Map<ErrorCode, String> errors;
  final List<Example> examples;

  /// Needs the Flutter SDK or long-running processes: implemented in `engine_cli`, not served by `engine_api` (v1).
  final bool requiresFlutter;

  /// Calling twice with the same arguments has the same effect as once.
  final bool idempotent;
  final String since;
  final Deprecation? deprecated;
  final CliHints cli;

  String get group => name.split('.').first;
  String get verb => name.split('.').last;

  /// Parameters the registry adds to every non-read operation.
  List<Param> get implicitParams => kind == OperationKind.read
      ? const []
      : const [
          Param(
            'apply',
            ParamType.boolean,
            description:
                'Write now (default for write operations) or only preview (default for destructive ones).',
          ),
          Param(
            'confirmation',
            ParamType.string,
            description:
                'The token returned by the preview of a destructive operation; applies exactly that change.',
          ),
        ];

  Operation copyWith({OpHandler? handler, bool? requiresFlutter}) => Operation(
    name: name,
    summary: summary,
    description: description,
    kind: kind,
    scope: scope,
    handler: handler ?? this.handler,
    params: params,
    result: result,
    errors: errors,
    examples: examples,
    requiresFlutter: requiresFlutter ?? this.requiresFlutter,
    idempotent: idempotent,
    since: since,
    deprecated: deprecated,
    cli: cli,
  );
}
