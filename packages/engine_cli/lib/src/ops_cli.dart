import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:engine_core/engine_core_ops.dart';
import 'package:path/path.dart' as p;

import 'image_codec.dart';

/// Walks up from [from] looking for `docs/getting-started.md` (monorepo layout).
String? findDocsRoot({String? from}) {
  var dir = p.normalize(p.absolute(from ?? Directory.current.path));
  while (true) {
    final candidate = p.join(dir, 'docs');
    if (File(p.join(candidate, 'getting-started.md')).existsSync()) {
      return candidate;
    }
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

/// Where a command writes. Injected so tests read output without capturing the process streams.
class CliIo {
  CliIo({StringSink? out, StringSink? err, Stream<List<int>>? stdinStream})
    : out = out ?? stdout,
      err = err ?? stderr,
      stdinStream = stdinStream ?? stdin;

  final StringSink out;
  final StringSink err;
  final Stream<List<int>> stdinStream;
}

/// The project folder for a run: `--project`, or the nearest ancestor of the working directory with a
/// `pubspec.yaml`, or null (pure operations still work).
String? findProjectRoot(String? flag, {String? from}) {
  if (flag != null) return p.normalize(p.absolute(flag));
  var dir = p.normalize(p.absolute(from ?? Directory.current.path));
  while (true) {
    if (File(p.join(dir, 'pubspec.yaml')).existsSync() &&
        Directory(p.join(dir, 'assets', 'levels')).existsSync())
      return dir;
    final parent = p.dirname(dir);
    if (parent == dir) return null;
    dir = parent;
  }
}

/// Adds a `game_agent <group> <verb>` command for every operation of [registry] to [runner]. A group that
/// already exists (`idle`, `studio`) gets the new verbs next to its own; a verb that already exists keeps its
/// hand-written command (the legacy one), so nothing that works today changes.
void addOperationCommands(
  CommandRunner<int> runner,
  OperationRegistry registry, {
  CliIo? io,
  OpContext Function(ArgResults global)? makeContext,
}) {
  runner.argParser
    ..addOption(
      'project',
      help:
          'The game project folder (default: the nearest folder with pubspec.yaml and assets/levels).',
    )
    ..addFlag(
      'read-only',
      negatable: false,
      help: 'Refuse every operation that would change files.',
    );
  final cliIo = io ?? CliIo();
  OpContext context(ArgResults global) {
    if (makeContext != null) return makeContext(global);
    final root = findProjectRoot(global['project'] as String?);
    return OpContext(
      project: root == null ? null : ProjectRoot(root),
      policy: Policy(readOnly: global['read-only'] == true),
      actor: 'cli',
      imageCodec: const PackageImageCodec(),
      docsRoot: findDocsRoot(),
    );
  }

  final groups = <String, Command<int>>{};
  for (final op in registry.all) {
    // Flutter-dependent operations keep their dedicated top-level commands (create, upgrade, build-release).
    if (op.requiresFlutter) continue;
    final groupName = op.cli.group ?? op.group;
    final group = groups.putIfAbsent(
      groupName,
      () => runner.commands[groupName] ?? _GroupCommand(groupName),
    );
    if (group is _GroupCommand && !runner.commands.containsKey(groupName))
      runner.addCommand(group);
    final verb = op.cli.verb ?? op.verb.replaceAll('_', '-');
    if (group.subcommands.containsKey(verb)) continue;
    group.addSubcommand(_OpCommand(op, registry, context, cliIo));
  }
}

class _GroupCommand extends Command<int> {
  _GroupCommand(this.name);

  @override
  final String name;
  @override
  String get description =>
      'Operations of the "$name" group (run `game_agent $name <verb> --help`).';
}

class _OpCommand extends Command<int> {
  _OpCommand(this.op, this.registry, this.context, this.io) {
    for (final param in op.params.where((p) => !p.positional)) {
      _addOption(argParser, param);
    }
    argParser
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print the exact result envelope as JSON.',
      )
      ..addFlag(
        'stdin',
        negatable: false,
        help: 'Read a JSON object of parameters from standard input.',
      )
      ..addOption(
        'args',
        help: 'Parameters as one JSON object (flags win over it).',
      );
    if (op.kind != OperationKind.read) {
      argParser
        ..addFlag(
          'dry-run',
          negatable: false,
          help: 'Preview the change without writing.',
        )
        ..addFlag(
          'apply',
          negatable: false,
          help: 'Apply (needed for destructive operations).',
        )
        ..addFlag(
          'yes',
          negatable: false,
          help: 'Preview, then apply without asking.',
        )
        ..addOption(
          'confirmation',
          help: 'The token from a destructive preview.',
        );
    }
  }

  final Operation op;
  final OperationRegistry registry;
  final OpContext Function(ArgResults) context;
  final CliIo io;

  @override
  String get name => op.cli.verb ?? op.verb.replaceAll('_', '-');
  @override
  String get description => op.summary;
  @override
  String get invocation =>
      'game_agent ${op.cli.group ?? op.group} $name ${[for (final p in op.params.where((p) => p.positional)) p.required ? '<${p.name}>' : '[${p.name}]'].join(' ')}'
          .trimRight();
  @override
  String get usageFooter => '\n${op.description}\n\nKind: ${op.kind.name}.';

  static void _addOption(ArgParser parser, Param p) {
    final flag =
        p.cliFlag ??
        p.name.replaceAllMapped(
          RegExp('[A-Z]'),
          (m) => '-${m[0]!.toLowerCase()}',
        );
    switch (p.type) {
      case ParamType.boolean:
        parser.addFlag(flag, help: p.description, defaultsTo: null);
      case ParamType.array:
        parser.addMultiOption(flag, help: p.description);
      case ParamType.enumeration:
        parser.addOption(
          flag,
          abbr: p.cliAbbr,
          allowed: p.options,
          help: p.description,
        );
      default:
        parser.addOption(flag, abbr: p.cliAbbr, help: p.description);
    }
  }

  Future<Map<String, Object?>> _collect() async {
    final r = argResults!;
    final args = <String, Object?>{};
    if (r['args'] != null)
      args.addAll(
        (jsonDecode(r['args'] as String) as Map).cast<String, Object?>(),
      );
    if (r['stdin'] == true) {
      final text = await utf8.decodeStream(io.stdinStream);
      if (text.trim().isNotEmpty)
        args.addAll((jsonDecode(text) as Map).cast<String, Object?>());
    }
    final positional = op.params.where((p) => p.positional).toList();
    for (var i = 0; i < positional.length && i < r.rest.length; i++) {
      args[positional[i].name] = r.rest[i];
    }
    for (final param in op.params.where((p) => !p.positional)) {
      final flag =
          param.cliFlag ??
          param.name.replaceAllMapped(
            RegExp('[A-Z]'),
            (m) => '-${m[0]!.toLowerCase()}',
          );
      if (!r.wasParsed(flag)) continue;
      final v = r[flag];
      args[param.name] = param.type == ParamType.json && v is String
          ? _json(v)
          : v;
    }
    if (op.kind != OperationKind.read) {
      if (r['dry-run'] == true) args['apply'] = false;
      if (r['apply'] == true) args['apply'] = true;
      if (r['confirmation'] != null) args['confirmation'] = r['confirmation'];
    }
    return args;
  }

  static Object? _json(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  @override
  Future<int> run() async {
    final Map<String, Object?> args;
    try {
      args = await _collect();
    } on FormatException catch (e) {
      io.err.writeln(
        'Error: the JSON given with --args/--stdin is not valid (${e.message}).',
      );
      return ErrorCode.invalidParams.exit;
    }
    final ctx = context(globalResults!);
    var result = await registry.call(op.name, args, ctx);
    final asJson = argResults!['json'] == true;
    if (op.kind == OperationKind.destructive &&
        argResults!['yes'] == true &&
        result.ok &&
        result.data is Map &&
        (result.data! as Map)['preview'] == true &&
        (result.data! as Map)['confirmation'] != null) {
      if (!asJson) _printPreview(result.data! as Map);
      result = await registry.call(op.name, {
        ...args,
        'confirmation': (result.data! as Map)['confirmation'],
      }, ctx);
    }
    if (asJson) {
      io.out.writeln(
        const JsonEncoder.withIndent('  ').convert(result.toJson()),
      );
    } else {
      _print(result);
    }
    if (!result.ok) return result.error!.code.exit;
    final d = result.data;
    if (op.kind == OperationKind.destructive &&
        d is Map &&
        d['preview'] == true &&
        d['confirmation'] != null) {
      if (!asJson)
        io.err.writeln('This is a preview. Run again with --yes to apply it.');
      return ErrorCode.confirmationRequired.exit;
    }
    if (op.name == 'level.validate' ||
        op.name == 'project.validate' ||
        op.name == 'idle.validate') {
      if (d is Map && d['ok'] == false) return 1;
    }
    return 0;
  }

  void _printPreview(Map preview) {
    io.out.writeln(preview['summary']);
    for (final f
        in ((preview['diff'] as Map?)?['files'] as List? ?? const [])) {
      final m = f as Map;
      io.out.writeln('  ${m['change']} ${m['path']}');
      if (m['text'] != null) io.out.writeln(_indent(m['text']! as String));
    }
  }

  static String _indent(String s) =>
      s.split('\n').map((l) => '    $l').join('\n');

  void _print(OpResult r) {
    if (!r.ok) {
      final e = r.error!;
      io.err.writeln('Error (${e.code.code}): ${e.message}');
      for (final pr in (e.details?['problems'] as List? ?? const [])) {
        io.err.writeln('  $pr');
      }
      if (e.hint != null) io.err.writeln('Hint: ${e.hint}');
      return;
    }
    for (final w in r.warnings) {
      io.err.writeln('Warning: $w');
    }
    final d = r.data;
    if (d is Map && d['preview'] == true) {
      _printPreview(d);
      return;
    }
    if (d is Map && d['text'] is String) {
      io.out.write(d['text']);
      if (!(d['text']! as String).endsWith('\n')) io.out.writeln();
    } else if (d != null) {
      io.out.writeln(const JsonEncoder.withIndent('  ').convert(d));
    }
    if (r.undoId != null)
      io.err.writeln('Undo with: game_agent undo undo (entry ${r.undoId})');
  }
}
