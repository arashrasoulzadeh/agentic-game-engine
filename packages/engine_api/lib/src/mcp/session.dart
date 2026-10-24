import 'dart:convert';

import 'package:engine_core/engine_core_ops.dart';

import '../version.dart';
import 'rpc.dart';
import 'tools.dart';

/// The MCP revision this server speaks; a client asking for another gets this one back.
const mcpProtocolVersion = '2025-06-18';

const _pageSize = 100;

/// One MCP conversation: owns the [OpContext] (so an opened project lives for the session) and answers the
/// protocol methods over the shared operation registry.
class McpSession {
  McpSession(this.registry, this.ctx, {this.underscoreNames = false});

  final OperationRegistry registry;
  final OpContext ctx;

  /// Expose `level_add_entity` instead of `level.add_entity` for clients that reject dots in tool names.
  final bool underscoreNames;

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
  Future<Object?> dispatch(String method, Map<String, Object?> params) async {
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
      case 'notifications/initialized' || 'notifications/cancelled':
        return null;
      case 'ping':
        return <String, Object?>{};
      case 'tools/list':
        return _toolsList(params);
      case 'tools/call':
        return _toolsCall(params);
      case 'resources/list':
        return {
          'resources': [
            _resource('engine://operations', 'Operation catalogue'),
            _resource('engine://schemas/components', 'Component names'),
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
          ],
        };
      case 'resources/read':
        return _resourcesRead(params);
      case 'prompts/list':
        return {'prompts': <Object?>[]};
      case 'logging/setLevel':
        return <String, Object?>{};
      default:
        throw RpcException(-32601, 'Method not found: $method');
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

  Future<Object?> _toolsCall(Map<String, Object?> params) async {
    final name = params['name'];
    if (name is! String) throw RpcException(-32602, 'name is required');
    final op = _byWire(name);
    if (op == null) throw RpcException(-32602, 'Unknown tool: $name');
    final args = params['arguments'];
    if (args != null && args is! Map) {
      throw RpcException(-32602, 'arguments must be an object');
    }
    return callTool(
      registry,
      ctx,
      op.name,
      (args as Map?)?.cast<String, Object?>() ?? {},
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
