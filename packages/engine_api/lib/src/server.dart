import 'dart:io';

import 'package:args/args.dart';
import 'package:engine_core/engine_core_ops.dart';

import 'http/http_server.dart';
import 'http/token.dart';
import 'mcp/session.dart';
import 'request_log.dart';
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
  ..addOption(
    'log',
    help: 'Request log file (default: <project>/.studio/api-requests.jsonl).',
  )
  ..addOption(
    'max-result-bytes',
    defaultsTo: '8388608',
    help: 'Larger results become a too_large error.',
  )
  ..addOption(
    'requests-per-minute',
    defaultsTo: '120',
    help: 'HTTP rate limit.',
  )
  ..addFlag(
    'http',
    negatable: false,
    help: 'Serve REST, JSON-RPC and MCP over HTTP instead of MCP over stdio.',
  )
  ..addOption(
    'port',
    defaultsTo: '7421',
    help: 'HTTP port (0 = pick a free one).',
  )
  ..addOption(
    'bind',
    defaultsTo: '127.0.0.1',
    help: 'HTTP address to listen on.',
  )
  ..addFlag(
    'allow-remote',
    negatable: false,
    help: 'Allow --bind beyond localhost (no TLS here; use a reverse proxy).',
  )
  ..addOption(
    'token',
    help: 'Bearer token (default: ENGINE_API_TOKEN or .studio/api-token).',
  )
  ..addFlag('rotate-token', negatable: false, help: 'Replace the stored token.')
  ..addFlag('print-token', negatable: false, help: 'Print the token to stderr.')
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
    maxResultBytes: int.tryParse(r['max-result-bytes'] as String) ?? 8388608,
    log: _requestLog(r['log'] as String?, project),
  );
  if (!(r['http'] as bool)) {
    await serveStdio(session, input ?? stdin, out);
    return 0;
  }
  final token = resolveToken(
    explicit:
        (r['token'] as String?) ?? Platform.environment['ENGINE_API_TOKEN'],
    projectRoot: project?.root,
    rotate: r['rotate-token'] as bool,
  );
  final EngineHttpServer server;
  try {
    server = await EngineHttpServer.start(
      session,
      token: token,
      host: r['bind'] as String,
      port: int.tryParse(r['port'] as String) ?? 7421,
      allowRemote: r['allow-remote'] as bool,
      requestsPerMinute:
          int.tryParse(r['requests-per-minute'] as String) ?? 120,
    );
  } on Object catch (e) {
    error('Cannot start the HTTP server: $e');
    return 69;
  }
  error('engine_api: listening on http://${r['bind']}:${server.port}');
  if (project != null && r['token'] == null) {
    error('engine_api: bearer token in ${project.root}/.studio/api-token');
  }
  if (r['print-token'] as bool) error('engine_api: token $token');
  await ProcessSignal.sigint.watch().first;
  await server.close();
  return 0;
}

RequestLog? _requestLog(String? explicit, ProjectRoot? project) {
  if (explicit != null) return RequestLog(explicit);
  if (project == null) return null;
  return RequestLog('${project.root}/.studio/api-requests.jsonl');
}
