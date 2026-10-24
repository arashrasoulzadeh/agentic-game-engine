import 'dart:io';

import 'package:args/args.dart';
import 'package:engine_core/engine_core_ops.dart';

import 'mcp/session.dart';
import 'mcp/stdio.dart';
import 'version.dart';

ArgParser buildServerParser() => ArgParser()
  ..addFlag('version', abbr: 'v', negatable: false, help: 'Print the version.')
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addOption('project', abbr: 'p', help: 'Open this project folder at start.')
  ..addFlag(
    'read-only',
    negatable: false,
    help: 'Refuse every operation that would change files.',
  )
  ..addMultiOption('allow', help: 'Only serve operations matching this glob.')
  ..addMultiOption('deny', help: 'Hide operations matching this glob.')
  ..addFlag(
    'underscore-tool-names',
    negatable: false,
    help: 'Expose level_add_entity instead of level.add_entity.',
  );

/// Runs the server: MCP over stdio for now. Returns the process exit code.
Future<int> runServer(
  List<String> args, {
  Stream<List<int>>? input,
  void Function(String line)? write,
  void Function(String line)? err,
}) async {
  final out = write ?? (l) => stdout.writeln(l);
  final error = err ?? (l) => stderr.writeln(l);
  final ArgResults r;
  try {
    r = buildServerParser().parse(args);
  } on FormatException catch (e) {
    error(e.message);
    return 64;
  }
  if (r['version'] as bool) {
    out('engine_api $engineApiVersion');
    return 0;
  }
  if (r['help'] as bool) {
    out('engine_api: MCP server over stdio.\n\n${buildServerParser().usage}');
    return 0;
  }
  ProjectRoot? project;
  final path = r['project'] as String?;
  if (path != null) {
    try {
      project = ProjectRoot(path);
    } on Object catch (e) {
      error('Cannot open project: $e');
      return 66;
    }
  }
  final ctx = OpContext(
    project: project,
    policy: Policy(
      allow: (r['allow'] as List).cast<String>(),
      deny: (r['deny'] as List).cast<String>(),
      readOnly: r['read-only'] as bool,
    ),
    log: error,
  );
  final session = McpSession(
    buildRegistry(),
    ctx,
    underscoreNames: r['underscore-tool-names'] as bool,
  );
  await serveStdio(session, input ?? stdin, out);
  return 0;
}
