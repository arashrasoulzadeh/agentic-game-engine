/// Pieces that need `dart:io`: network transports (sockets) and advisory file locks. Import this alongside
/// `package:engine_core/engine_core.dart` in a server, a command-line tool or a
/// desktop/mobile game; it is deliberately not exported from the main library so
/// that library keeps compiling for the web.
///
/// For a browser client, implement `NetEndpoint` over `package:web_socket_channel`
/// or `dart:html` - it is a dozen lines, and [WebSocketEndpoint] below is the
/// template.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'engine_core.dart';

export 'src/io/atomic_save.dart';
export 'src/io/file_lock.dart';

/// A [NetEndpoint] over a `dart:io` [WebSocket]: each message is one JSON text frame.
///
/// Malformed frames (not JSON, or JSON that is not an object) are dropped rather than
/// thrown: a hostile or buggy peer must not be able to crash the host by sending
/// garbage.
class WebSocketEndpoint implements NetEndpoint {
  WebSocketEndpoint(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onDone: _closed,
      onError: (Object _) => _closed(),
      cancelOnError: true,
    );
  }

  final WebSocket _socket;
  late final StreamSubscription<dynamic> _subscription;
  bool _isClosed = false;

  /// Frames dropped as malformed - for diagnostics and tests.
  int malformedFrames = 0;

  @override
  void Function(Map<String, dynamic> message)? onMessage;

  @override
  void Function()? onClose;

  void _onData(dynamic data) {
    if (data is! String) {
      malformedFrames++;
      return;
    }
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) {
        malformedFrames++;
        return;
      }
      onMessage?.call(decoded.cast<String, dynamic>());
    } on FormatException {
      malformedFrames++;
    }
  }

  void _closed() {
    if (_isClosed) return;
    _isClosed = true;
    onClose?.call();
  }

  @override
  void send(Map<String, dynamic> message) {
    if (_isClosed) return;
    _socket.add(jsonEncode(message));
  }

  @override
  void close() {
    if (_isClosed) return;
    _closed();
    _subscription.cancel();
    _socket.close();
  }
}

/// Connects to a WebSocket server at [url] (`ws://host:port/path`).
Future<NetEndpoint> connectWebSocket(String url) async =>
    WebSocketEndpoint(await WebSocket.connect(url));

/// A listening WebSocket server. Each accepted connection becomes a [NetEndpoint]
/// handed to [onConnection] - typically `hostSession.accept`.
class WebSocketListener {
  WebSocketListener._(this._server);

  final HttpServer _server;

  /// The port actually bound (useful when you asked for port 0).
  int get port => _server.port;

  /// `ws://` URL clients can connect to on this machine.
  String get localUrl => 'ws://127.0.0.1:$port';

  /// Starts listening on [host]:[port] (port 0 picks a free one). Non-WebSocket
  /// requests get a 426 and are ignored.
  static Future<WebSocketListener> bind(
    void Function(NetEndpoint endpoint) onConnection, {
    Object host = '127.0.0.1',
    int port = 0,
  }) async {
    final server = await HttpServer.bind(host, port);
    server.listen((request) async {
      if (!WebSocketTransformer.isUpgradeRequest(request)) {
        request.response
          ..statusCode = HttpStatus.upgradeRequired
          ..close();
        return;
      }
      onConnection(
        WebSocketEndpoint(await WebSocketTransformer.upgrade(request)),
      );
    });
    return WebSocketListener._(server);
  }

  Future<void> close() => _server.close(force: true);
}
