import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// One open `GET /mcp` event stream and the listeners waiting on it.
class McpSseSession {
  McpSseSession(this.id);

  final String id;
  final List<HttpResponse> _streams = [];
  bool closed = false;

  bool get hasListeners => _streams.isNotEmpty;

  void add(HttpResponse response) {
    if (closed) {
      response.statusCode = 404;
      unawaited(response.close());
      return;
    }
    _streams.add(response);
  }

  void remove(HttpResponse response) => _streams.remove(response);

  /// Writes one SSE `message` event (JSON-RPC notification or response).
  void send(Object payload) {
    if (closed || _streams.isEmpty) return;
    final chunk =
        'event: message\ndata: ${jsonEncode(payload)}\n\n';
    final dead = <HttpResponse>[];
    for (final s in _streams) {
      try {
        s.write(chunk);
      } catch (_) {
        dead.add(s);
      }
    }
    for (final s in dead) {
      _streams.remove(s);
    }
  }

  Future<void> close() async {
    closed = true;
    final copy = List<HttpResponse>.from(_streams);
    _streams.clear();
    for (final s in copy) {
      try {
        await s.close();
      } catch (_) {}
    }
  }
}

/// Allocates MCP streamable-HTTP session ids and routes SSE payloads to them.
class McpSseHub {
  final Map<String, McpSseSession> _sessions = {};
  final _random = Random.secure();

  /// Creates a new session id (returned on `initialize` as `Mcp-Session-Id`).
  String create() {
    final id = List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _sessions[id] = McpSseSession(id);
    return id;
  }

  McpSseSession? operator [](String id) => _sessions[id];

  Future<void> delete(String id) async {
    final s = _sessions.remove(id);
    await s?.close();
  }

  /// Broadcasts [payload] to every open stream of [id], if any.
  void send(String id, Object payload) => _sessions[id]?.send(payload);

  Future<void> closeAll() async {
    final all = _sessions.values.toList();
    _sessions.clear();
    for (final s in all) {
      await s.close();
    }
  }
}
