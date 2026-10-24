import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';

import '../mcp/rpc.dart';
import '../mcp/session.dart';
import '../version.dart';
import 'openapi.dart';
import 'token.dart';

const _json = 'application/json; charset=utf-8';

/// REST (`/v1`), JSON-RPC (`/rpc`) and MCP (`/mcp`) on one port, all backed by the same [McpSession] so an opened
/// project, the policy and the undo journal are shared by every transport.
class EngineHttpServer {
  EngineHttpServer._(this._server, this._session, this._token, this._maxBody);

  final HttpServer _server;
  final McpSession _session;
  final String _token;
  final int _maxBody;
  Future<void> _writes = Future.value();

  /// The bound port (useful with `port: 0`).
  int get port => _server.port;

  /// Binds [host]:[port] and starts serving. A non-loopback [host] is refused unless [allowRemote] is set.
  static Future<EngineHttpServer> start(
    McpSession session, {
    required String token,
    String host = '127.0.0.1',
    int port = 0,
    bool allowRemote = false,
    int maxRequestBytes = 1048576,
  }) async {
    final loopback =
        host == '127.0.0.1' || host == '::1' || host == 'localhost';
    if (!loopback && !allowRemote) {
      throw ArgumentError(
        'Refusing to bind $host: pass --allow-remote to listen beyond localhost (TLS is not terminated here).',
      );
    }
    final server = await HttpServer.bind(host, port);
    final s = EngineHttpServer._(server, session, token, maxRequestBytes);
    unawaited(server.forEach(s._handle));
    return s;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final requestId =
        req.headers.value('x-request-id') ??
        DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    req.response.headers
      ..set('x-request-id', requestId)
      ..contentType = ContentType.parse(_json);
    try {
      if (!_hostAllowed(req)) {
        return _send(req, 403, _fail(ErrorCode.forbidden, 'Host not allowed.'));
      }
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/v1/health') {
        return _send(req, 200, {
          'status': 'ok',
          'version': engineApiVersion,
          'uptimeMs': _session.ctx
              .clock()
              .difference(_session.ctx.startedAt)
              .inMilliseconds,
        });
      }
      if (!_authorized(req)) {
        req.response.headers.set('www-authenticate', 'Bearer');
        return _send(
          req,
          401,
          _fail(ErrorCode.forbidden, 'A valid bearer token is required.'),
        );
      }
      if (path == '/mcp') return await _mcp(req);
      if (path == '/rpc') return await _rpc(req);
      if (path.startsWith('/v1/')) return await _rest(req, path.substring(4));
      return _send(req, 404, _fail(ErrorCode.notFound, 'No such path: $path'));
    } on _TooLarge {
      await _send(
        req,
        413,
        _fail(ErrorCode.tooLarge, 'The request body is over $_maxBody bytes.'),
      );
    } on FormatException {
      await _send(req, 400, _fail(ErrorCode.invalidParams, 'Malformed JSON.'));
    } catch (e) {
      _session.ctx.log('http error: $e');
      await _send(req, 500, _fail(ErrorCode.internal, 'Internal error.'));
    }
  }

  /// Rejects Host headers that are not the loopback names, which is what stops DNS rebinding from a web page.
  bool _hostAllowed(HttpRequest req) {
    if (_server.address.isLoopback == false) return true;
    final host = req.headers.host;
    return host == null ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]';
  }

  bool _authorized(HttpRequest req) {
    final header = req.headers.value('authorization') ?? '';
    return header.startsWith('Bearer ') &&
        tokensMatch(header.substring(7), _token);
  }

  Map<String, Object?> _fail(ErrorCode code, String message) => {
    'ok': false,
    'error': OpError(code, message).toJson(),
  };

  Future<void> _send(HttpRequest req, int status, Object? body) async {
    req.response.statusCode = status;
    req.response.write(jsonEncode(body));
    await req.response.close();
  }

  Future<Object?> _readBody(HttpRequest req) async {
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBody) throw _TooLarge();
    }
    if (bytes.isEmpty) return null;
    return jsonDecode(utf8.decode(bytes));
  }

  /// Serialises writes (one project, one mutex) while letting reads overlap.
  Future<T> _run<T>(Operation? op, Future<T> Function() job) {
    if (op == null || op.kind == OperationKind.read) return job();
    final next = _writes.then((_) => job());
    _writes = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _rest(HttpRequest req, String rest) async {
    if (rest == 'openapi.json' && req.method == 'GET') {
      return _send(
        req,
        200,
        openApiFor([
          for (final o in _session.registry.visibleTo(_session.ctx))
            if (!o.requiresFlutter) o,
        ]),
      );
    }
    if (req.method == 'GET' && rest.startsWith('engine/operations')) {
      final name = rest.length > 'engine/operations/'.length
          ? rest.substring('engine/operations/'.length)
          : null;
      final args = name != null
          ? <String, Object?>{'name': name}
          : {
              for (final k in ['group', 'kind'])
                if (req.uri.queryParameters[k] != null)
                  k: req.uri.queryParameters[k],
            };
      final r = await _session.registry.call(
        name != null ? 'engine.operation' : 'engine.operations',
        args,
        _session.ctx,
      );
      return _send(req, r.ok ? 200 : r.error!.code.http, r.toJson());
    }
    final parts = rest.split('/');
    final op = parts.length == 2
        ? _session.registry.lookup(
            '${parts[0]}.${parts[1].replaceAll('-', '_')}',
          )
        : null;
    if (op == null ||
        op.requiresFlutter ||
        !_session.ctx.policy.visible(op.name)) {
      return _send(
        req,
        404,
        _fail(ErrorCode.notFound, 'Unknown operation: /v1/$rest'),
      );
    }
    if (req.method != 'POST') {
      req.response.headers.set('allow', 'POST');
      return _send(req, 405, _fail(ErrorCode.invalidParams, 'Use POST.'));
    }
    final body = await _readBody(req);
    if (body != null && body is! Map) {
      return _send(
        req,
        400,
        _fail(ErrorCode.invalidParams, 'The body must be a JSON object.'),
      );
    }
    final r = await _run(
      op,
      () => _session.registry.call(
        op.name,
        (body as Map?)?.cast<String, Object?>() ?? {},
        _session.ctx,
      ),
    );
    return _send(req, r.ok ? 200 : r.error!.code.http, r.toJson());
  }

  Future<void> _rpc(HttpRequest req) async {
    if (req.method != 'POST') {
      return _send(req, 405, _fail(ErrorCode.invalidParams, 'Use POST.'));
    }
    final body = await _readBody(req);
    final reply = await handleRpc(body, (method, params) async {
      if (method == 'rpc.discover') {
        return [
          for (final o in _session.registry.visibleTo(_session.ctx))
            if (!o.requiresFlutter) operationSummaryJson(o),
        ];
      }
      final op = _session.registry.lookup(method);
      if (op == null ||
          op.requiresFlutter ||
          !_session.ctx.policy.visible(method)) {
        throw RpcException(-32601, 'Method not found: $method');
      }
      final r = await _run(
        op,
        () => _session.registry.call(method, params, _session.ctx),
      );
      if (!r.ok) {
        final e = r.error!;
        throw RpcException(e.code.rpc, e.message, {
          'code': e.code.code,
          if (e.details != null) 'details': e.details,
          if (e.hint != null) 'hint': e.hint,
        });
      }
      return {
        'data': r.data,
        'meta': {
          'warnings': r.warnings,
          if (r.diff != null) 'diff': r.diff,
          if (r.undoId != null) 'undoId': r.undoId,
          'durationMs': r.durationMs,
        },
      };
    });
    if (reply == null) {
      req.response.statusCode = 204;
      return req.response.close();
    }
    return _send(req, 200, reply);
  }

  Future<void> _mcp(HttpRequest req) async {
    if (req.method != 'POST') {
      return _send(req, 405, _fail(ErrorCode.invalidParams, 'Use POST.'));
    }
    final body = await _readBody(req);
    final reply = await handleRpc(
      body,
      (m, p) => _run(null, () => _session.dispatch(m, p)),
    );
    if (reply == null) {
      req.response.statusCode = 202;
      return req.response.close();
    }
    return _send(req, 200, reply);
  }
}

class _TooLarge implements Exception {}
