import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';

import '../request_log.dart';
import 'prompts.dart';
import '../version.dart';
import 'rpc.dart';
import 'tools.dart';

/// The MCP revision this server speaks; a client asking for another gets this one back.
const mcpProtocolVersion = '2025-06-18';

const _pageSize = 100;

/// One MCP conversation: owns the [OpContext] (so an opened project lives for the session) and answers the
/// protocol methods over the shared operation registry.
class McpSession {
  McpSession(
    this.registry,
    this.ctx, {
    this.underscoreNames = false,
    this.log,
    this.maxResultBytes = 8 * 1024 * 1024,
  });

  /// Where every call is recorded, if anywhere.
  final RequestLog? log;

  /// Larger results are replaced by a `too_large` error so one call cannot flood a client.
  final int maxResultBytes;

  final OperationRegistry registry;
  final OpContext ctx;

  /// Expose `level_add_entity` instead of `level.add_entity` for clients that reject dots in tool names.
  final bool underscoreNames;

  /// In-flight JSON-RPC request ids → tokens, for `notifications/cancelled`.
  final Map<Object, CancellationToken> _inFlight = {};

  /// Runs one operation for any transport: applies the result size limit and records the call in the request log.
  ///
  /// When [rpcId] is set the call is cancellable via `notifications/cancelled`
  /// with that same id (as `requestId`).
  Future<OpResult> invoke(
    String name,
    Map<String, Object?> args, {
    String transport = 'mcp',
    String? requestId,
    Object? rpcId,
  }) async {
    final token = rpcId != null ? CancellationToken() : null;
    if (rpcId != null && token != null) _inFlight[rpcId] = token;
    try {
      var result = await registry.call(
        name,
        args,
        ctx,
        cancellation: token,
      );
      var bytes = jsonEncode(result.toJson()).length;
      if (bytes > maxResultBytes) {
        result = OpResult.failure(
          OpError(
            ErrorCode.tooLarge,
            'The result is $bytes bytes; the limit is $maxResultBytes.',
            hint: 'Narrow the request (paths, limit, offset).',
          ),
          durationMs: result.durationMs,
        );
        bytes = jsonEncode(result.toJson()).length;
      }
      final op = registry.lookup(name);
      log?.write({
        'ts': ctx.clock().toUtc().toIso8601String(),
        if (requestId != null) 'requestId': requestId,
        if (rpcId != null) 'rpcId': '$rpcId',
        'transport': transport,
        'actor': ctx.actor,
        'op': name,
        if (op != null) 'kind': op.kind.name,
        'ok': result.ok,
        if (!result.ok) 'code': result.error!.code.code,
        'durationMs': result.durationMs,
        'bytesOut': bytes,
        'project': ctx.project?.root,
        if (result.undoId != null) 'undoId': result.undoId,
      });
      return result;
    } finally {
      if (rpcId != null) _inFlight.remove(rpcId);
    }
  }

  /// Marks the in-flight call with JSON-RPC id [requestId] cancelled, if any.
  void cancel(Object requestId) => _inFlight[requestId]?.cancel();

  String _wire(String name) =>
      underscoreNames ? name.replaceAll('.', '_') : name;

  List<Operation> get _served => [
    for (final op in registry.visibleTo(ctx))
      if (!op.requiresFlutter) op,
  ];

  Operation? _byWire(String name) {
    for (final op in _served) {
      if (_wire(op.name) == name) return op;
    }
    return null;
  }

  /// Handles one JSON-RPC [method]; throws [RpcException] for protocol errors.
  ///
  /// [id] is the JSON-RPC request id (null for notifications). Long `tools/call`
  /// invocations register under that id so `notifications/cancelled` can stop them.
  Future<Object?> dispatch(
    String method,
    Map<String, Object?> params, {
    Object? id,
  }) async {
    switch (method) {
      case 'initialize':
        return {
          'protocolVersion': mcpProtocolVersion,
          'capabilities': {
            'tools': {'listChanged': false},
            'resources': {'subscribe': false, 'listChanged': false},
            'prompts': {'listChanged': false},
          },
          'serverInfo': {'name': 'engine_api', 'version': engineApiVersion},
          'instructions':
              'Call project.open with an absolute project folder first. Writes apply immediately and can be undone '
              'with undo.undo; destructive operations return a preview and a confirmation token to send back. '
              'engine.operations lists everything.',
        };
      case 'notifications/initialized':
        return null;
      case 'notifications/cancelled':
        final rid = params['requestId'];
        if (rid != null) cancel(rid);
        return null;
      case 'ping':
        return <String, Object?>{};
      case 'tools/list':
        return _toolsList(params);
      case 'tools/call':
        return _toolsCall(params, requestId: id);
      case 'resources/list':
        return {
          'resources': [
            _resource('engine://operations', 'Operation catalogue'),
            _resource('engine://schemas/components', 'Component names'),
            _resource('project://info', 'Open project'),
            _resource('project://tree', 'Project file tree'),
            _resource('project://problems', 'Project problems'),
            _resource('project://undo', 'Undo journal'),
          ],
        };
      case 'resources/templates/list':
        return {
          'resourceTemplates': [
            {
              'uriTemplate': 'engine://operations/{name}',
              'name': 'Operation spec',
              'mimeType': 'application/json',
            },
            {
              'uriTemplate': 'engine://schemas/components/{name}',
              'name': 'Component schema',
              'mimeType': 'application/json',
            },
            {
              'uriTemplate': 'project://levels/{name}',
              'name': 'Level',
              'mimeType': 'application/json',
            },
            {
              'uriTemplate': 'project://prefabs/{name}',
              'name': 'Prefab',
              'mimeType': 'application/json',
            },
            {
              'uriTemplate': 'project://graphs/{name}',
              'name': 'Graph',
              'mimeType': 'application/json',
            },
            {
              'uriTemplate': 'project://file/{path}',
              'name': 'Project text file',
              'mimeType': 'text/plain',
            },
          ],
        };
      case 'resources/read':
        return _resourcesRead(params);
      case 'prompts/list':
        return {
          'prompts': [for (final p in enginePrompts) p.toListJson()],
        };
      case 'prompts/get':
        return _promptsGet(params);
      case 'logging/setLevel':
        return <String, Object?>{};
      default:
        throw RpcException(-32601, 'Method not found: $method');
    }
  }

  Map<String, Object?> _promptsGet(Map<String, Object?> params) {
    final name = params['name'];
    final spec = enginePrompts.where((p) => p.name == name).firstOrNull;
    if (spec == null) throw RpcException(-32602, 'Unknown prompt: $name');
    try {
      final text = spec.render({
        for (final e in (params['arguments'] as Map? ?? const {}).entries)
          e.key as String: '${e.value}',
      });
      return {
        'description': spec.description,
        'messages': [
          {
            'role': 'user',
            'content': {'type': 'text', 'text': text},
          },
        ],
      };
    } on ArgumentError catch (e) {
      throw RpcException(-32602, e.message as String);
    }
  }

  Map<String, Object?> _resource(String uri, String name) => {
    'uri': uri,
    'name': name,
    'mimeType': 'application/json',
  };

  Map<String, Object?> _toolsList(Map<String, Object?> params) {
    final start = int.tryParse('${params['cursor'] ?? 0}') ?? 0;
    final all = _served;
    final page = all.skip(start).take(_pageSize).toList();
    return {
      'tools': [for (final op in page) toolFor(op, name: _wire(op.name))],
      if (start + _pageSize < all.length) 'nextCursor': '${start + _pageSize}',
    };
  }

  Future<Object?> _toolsCall(
    Map<String, Object?> params, {
    Object? requestId,
  }) async {
    final name = params['name'];
    if (name is! String) throw RpcException(-32602, 'name is required');
    final op = _byWire(name);
    if (op == null) throw RpcException(-32602, 'Unknown tool: $name');
    final args = params['arguments'];
    if (args != null && args is! Map) {
      throw RpcException(-32602, 'arguments must be an object');
    }
    return toolResult(
      await invoke(
        op.name,
        (args as Map?)?.cast<String, Object?>() ?? {},
        transport: 'mcp',
        rpcId: requestId,
      ),
    );
  }

  Future<Object?> _resourcesRead(Map<String, Object?> params) async {
    final uri = params['uri'];
    if (uri is! String) throw RpcException(-32602, 'uri is required');
    final (op, args) = switch (uri) {
      'engine://operations' => ('engine.operations', <String, Object?>{}),
      'engine://schemas/components' => (
        'schema.components',
        <String, Object?>{},
      ),
      _ when uri.startsWith('engine://operations/') => (
        'engine.operation',
        {'name': uri.substring('engine://operations/'.length)},
      ),
      _ when uri.startsWith('engine://schemas/components/') => (
        'schema.component',
        {'name': uri.substring('engine://schemas/components/'.length)},
      ),
      'project://info' => ('project.info', <String, Object?>{}),
      'project://tree' => ('project.tree', <String, Object?>{}),
      'project://problems' => ('project.problems', <String, Object?>{}),
      'project://undo' => ('undo.list', <String, Object?>{}),
      _ when uri.startsWith('project://levels/') => (
        'level.read',
        {
          'path':
              'assets/levels/${uri.substring('project://levels/'.length)}.json',
        },
      ),
      _ when uri.startsWith('project://prefabs/') => (
        'prefab.read',
        {'name': uri.substring('project://prefabs/'.length)},
      ),
      _ when uri.startsWith('project://graphs/') => (
        'graph.read',
        {'path': 'graphs/${uri.substring('project://graphs/'.length)}.json'},
      ),
      _ when uri.startsWith('project://file/') => (
        'project.read_file',
        {'path': uri.substring('project://file/'.length)},
      ),
      _ => throw RpcException(-32002, 'Unknown resource: $uri'),
    };
    final r = await registry.call(op, args, ctx);
    if (!r.ok) throw RpcException(-32002, r.error!.message);
    return {
      'contents': [
        {
          'uri': uri,
          'mimeType': 'application/json',
          'text': const JsonEncoder.withIndent('  ').convert(r.data),
        },
      ],
    };
  }
}
