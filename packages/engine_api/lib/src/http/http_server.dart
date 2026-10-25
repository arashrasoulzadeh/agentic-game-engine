import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:engine_core/engine_core_ops.dart';

import '../mcp/rpc.dart';
import '../mcp/session.dart';
import '../mcp/sse.dart';
import '../version.dart';
import 'openapi.dart';
import 'token.dart';

const _json = 'application/json; charset=utf-8';

/// REST (`/v1`), JSON-RPC (`/rpc`) and MCP (`/mcp`) on one port, all backed by the same [McpSession] so an opened
/// project, the policy and the undo journal are shared by every transport.
class EngineHttpServer {
  EngineHttpServer._(
    this._server,
    this._session,
    this._token,
    this._maxBody,
    this._perMinute,
    this._concurrent,
    this._origins,
  );

  final HttpServer _server;
  final McpSession _session;
  final String _token;
  final int _maxBody;
  final int _perMinute;
  final int _concurrent;
  final Set<String> _origins;
  final Map<String, int> _authFailures = {};
  final Map<String, _Stored> _idempotent = {};
  final List<DateTime> _recent = [];
  int _inFlight = 0;
  Future<void> _writes = Future.value();
  final McpSseHub _sse = McpSseHub();

  /// How long a client that keeps failing authentication is made to wait (after 5 failures).
  Duration authFailureDelay = const Duration(seconds: 1);

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
    int requestsPerMinute = 120,
    int concurrent = 4,
    List<String> allowedOrigins = const [],
  }) async {
    final loopback =
        host == '127.0.0.1' || host == '::1' || host == 'localhost';
    if (!loopback && !allowRemote) {
      throw ArgumentError(
        'Refusing to bind $host: pass --allow-remote to listen beyond localhost (TLS is not terminated here).',
      );
    }
    final server = await HttpServer.bind(host, port);
    final s = EngineHttpServer._(
      server,
      session,
      token,
      maxRequestBytes,
      requestsPerMinute,
      concurrent,
      allowedOrigins.toSet(),
    );
    session.progressSend = s._sse.send;
    unawaited(server.forEach(s._handle));
    return s;
  }

  Future<void> close() async {
    await _sse.closeAll();
    await _server.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    final requestId =
        req.headers.value('x-request-id') ??
        DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    req.response.headers
      ..set('x-request-id', requestId)
      ..contentType = ContentType.parse(_json);
    final origin = req.headers.value('origin');
    if (origin != null && _origins.contains(origin)) {
      req.response.headers
        ..set('access-control-allow-origin', origin)
        ..set('vary', 'Origin')
        ..set(
          'access-control-allow-headers',
          'authorization, content-type, idempotency-key, x-request-id',
        )
        ..set('access-control-allow-methods', 'GET, POST, DELETE, OPTIONS');
    }
    try {
      if (req.method == 'OPTIONS') {
        req.response.statusCode = 204;
        return await req.response.close();
      }
      if (!_hostAllowed(req)) {
        return await _send(
          req,
          403,
          _fail(ErrorCode.forbidden, 'Host not allowed.'),
        );
      }
      final path = req.uri.path;
      if (req.method == 'GET' && path == '/v1/health') {
        return await _send(req, 200, {
          'status': 'ok',
          'version': engineApiVersion,
          'uptimeMs': _session.ctx
              .clock()
              .difference(_session.ctx.startedAt)
              .inMilliseconds,
        });
      }
      final remote = req.connectionInfo?.remoteAddress.address ?? '?';
      if (!_authorized(req)) {
        final failures = _authFailures[remote] =
            (_authFailures[remote] ?? 0) + 1;
        if (failures > 5) await Future<void>.delayed(authFailureDelay);
        req.response.headers.set('www-authenticate', 'Bearer');
        return await _send(
          req,
          401,
          _fail(ErrorCode.unauthorized, 'A valid bearer token is required.'),
        );
      }
      _authFailures.remove(remote);
      final now = _session.ctx.clock();
      _recent.removeWhere((t) => now.difference(t).inSeconds >= 60);
      // SSE holds the socket open; do not count it against the concurrency cap.
      final isSse =
          path == '/mcp' &&
          req.method == 'GET' &&
          (req.headers.value('accept') ?? '').contains('text/event-stream');
      if (!isSse &&
          (_recent.length >= _perMinute || _inFlight >= _concurrent)) {
        req.response.headers.set('retry-after', '1');
        return await _send(
          req,
          429,
          _fail(ErrorCode.rateLimited, 'Too many requests; retry shortly.'),
        );
      }
      if (!isSse) {
        _recent.add(now);
        _inFlight++;
      }
      try {
        return await _route(req, path);
      } finally {
        if (!isSse) _inFlight--;
      }
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

  Future<void> _route(HttpRequest req, String path) async {
    if (path == '/mcp') return _mcp(req);
    if (path == '/rpc') return _rpc(req);
    if (path.startsWith('/v1/')) return _rest(req, path.substring(4));
    return _send(req, 404, _fail(ErrorCode.notFound, 'No such path: $path'));
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
    final key = op.kind == OperationKind.read
        ? null
        : req.headers.value('idempotency-key');
    final fingerprint = jsonEncode([op.name, body]);
    if (key != null) {
      final now = _session.ctx.clock();
      _idempotent.removeWhere((_, v) => now.isAfter(v.expires));
      final stored = _idempotent[key];
      if (stored != null) {
        if (stored.fingerprint != fingerprint) {
          return _send(
            req,
            409,
            _fail(
              ErrorCode.conflict,
              'That Idempotency-Key was already used with a different request.',
            ),
          );
        }
        return _send(req, stored.status, stored.body);
      }
    }
    final r = await _run(
      op,
      () => _session.invoke(
        op.name,
        (body as Map?)?.cast<String, Object?>() ?? {},
        transport: 'rest',
        requestId: req.response.headers.value('x-request-id'),
      ),
    );
    final status = r.ok ? 200 : r.error!.code.http;
    final json = r.toJson();
    if (key != null) {
      _idempotent[key] = _Stored(
        fingerprint,
        status,
        json,
        _session.ctx.clock().add(const Duration(minutes: 10)),
      );
    }
    return _send(req, status, json);
  }

  Future<void> _rpc(HttpRequest req) async {
    if (req.method != 'POST') {
      return _send(req, 405, _fail(ErrorCode.invalidParams, 'Use POST.'));
    }
    final body = await _readBody(req);
    final reply = await handleRpc(body, (method, params, {id}) async {
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
        () => _session.invoke(method, params, transport: 'rpc', rpcId: id),
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
    if (req.method == 'GET') return _mcpSse(req);
    if (req.method == 'DELETE') return _mcpDelete(req);
    if (req.method != 'POST') {
      return _send(
        req,
        405,
        _fail(ErrorCode.invalidParams, 'Use GET, POST or DELETE.'),
      );
    }
    final body = await _readBody(req);
    final sseId = req.headers.value('mcp-session-id');
    final reply = await handleRpc(
      body,
      (m, p, {id}) => _run(
        null,
        () => _session.dispatch(m, p, id: id, sseSessionId: sseId),
      ),
    );
    if (reply == null) {
      req.response.statusCode = 202;
      return req.response.close();
    }
    // Mint a session id on initialize so the client can open GET /mcp for SSE.
    if (body is Map &&
        body['method'] == 'initialize' &&
        reply is Map &&
        reply['result'] is Map) {
      req.response.headers.set('mcp-session-id', _sse.create());
    }
    return _send(req, 200, reply);
  }

  Future<void> _mcpSse(HttpRequest req) async {
    final accept = req.headers.value('accept') ?? '';
    if (!accept.contains('text/event-stream')) {
      return _send(
        req,
        405,
        _fail(
          ErrorCode.invalidParams,
          'GET /mcp requires Accept: text/event-stream.',
        ),
      );
    }
    var sessionId = req.headers.value('mcp-session-id');
    if (sessionId == null || _sse[sessionId] == null) {
      // Allow opening the stream before initialize: mint a session for this socket.
      sessionId = _sse.create();
    }
    final session = _sse[sessionId]!;
    final res = req.response;
    res.statusCode = 200;
    res.headers
      ..set('content-type', 'text/event-stream; charset=utf-8')
      ..set('cache-control', 'no-cache')
      ..set('connection', 'keep-alive')
      ..set('mcp-session-id', sessionId);
    // Disable buffering so heartbeats flush.
    res.bufferOutput = false;
    session.add(res);
    res.write(': connected\n\n');
    final done = Completer<void>();
    req.response.done.then((_) {
      session.remove(res);
      if (!done.isCompleted) done.complete();
    });
    // Heartbeat every 15s so proxies keep the socket; stop when the client goes away.
    Timer? beat;
    beat = Timer.periodic(const Duration(seconds: 15), (_) {
      try {
        res.write(': ping\n\n');
      } catch (_) {
        beat?.cancel();
        if (!done.isCompleted) done.complete();
      }
    });
    await done.future;
    beat.cancel();
  }

  Future<void> _mcpDelete(HttpRequest req) async {
    final id = req.headers.value('mcp-session-id');
    if (id == null) {
      return _send(
        req,
        400,
        _fail(ErrorCode.invalidParams, 'Mcp-Session-Id is required.'),
      );
    }
    if (_sse[id] == null) {
      return _send(req, 404, _fail(ErrorCode.notFound, 'Unknown MCP session.'));
    }
    await _sse.delete(id);
    req.response.statusCode = 204;
    await req.response.close();
  }
}

class _TooLarge implements Exception {}

class _Stored {
  _Stored(this.fingerprint, this.status, this.body, this.expires);
  final String fingerprint;
  final int status;
  final Object? body;
  final DateTime expires;
}
