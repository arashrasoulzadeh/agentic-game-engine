/// The browser transport: a [NetEndpoint] over the page's own `WebSocket`, for a Flutter web client talking to a
/// `HostSession` served by `WebSocketListener` (`engine_core_io.dart`). Import it only from code that compiles
/// for the web; the main library stays platform-neutral.
///
/// Browsers cannot listen for connections, so there is a client only. Use `wss://` when the page is served
/// over https - browsers refuse mixed content - and put authentication in the URL or a first message that
/// your host checks before accepting orders.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'engine_core.dart';

@JS('WebSocket')
extension type _JsWebSocket._(JSObject _) implements JSObject {
  external factory _JsWebSocket(String url);
  external void send(String data);
  external void close();
  external set onopen(JSFunction? handler);
  external set onmessage(JSFunction? handler);
  external set onclose(JSFunction? handler);
  external set onerror(JSFunction? handler);
}

/// A [NetEndpoint] over a browser `WebSocket` that is already open.
class BrowserWebSocketEndpoint implements NetEndpoint {
  BrowserWebSocketEndpoint._(this._socket) {
    _socket.onmessage = ((JSObject event) {
      final message = decodeNetFrame(
        event.getProperty<JSAny?>('data'.toJS)?.dartify(),
      );
      if (message == null) {
        malformedFrames++;
        return;
      }
      onMessage?.call(message);
    }).toJS;
    _socket.onclose = ((JSObject _) => _closed()).toJS;
    _socket.onerror = ((JSObject _) => _closed()).toJS;
  }

  final _JsWebSocket _socket;
  bool _isClosed = false;

  /// Frames dropped as malformed - for diagnostics and tests.
  int malformedFrames = 0;

  @override
  void Function(Map<String, dynamic> message)? onMessage;

  @override
  void Function()? onClose;

  void _closed() {
    if (_isClosed) return;
    _isClosed = true;
    onClose?.call();
  }

  @override
  void send(Map<String, dynamic> message) {
    if (_isClosed) return;
    _socket.send(encodeNetFrame(message));
  }

  @override
  void close() {
    if (_isClosed) return;
    _socket.close();
    _closed();
  }
}

/// Opens a WebSocket to [url] (`ws://` or `wss://`) and completes with an endpoint once it is open, or
/// throws a [StateError] if the connection fails first.
Future<NetEndpoint> connectBrowserWebSocket(String url) {
  final completer = Completer<NetEndpoint>();
  final socket = _JsWebSocket(url);
  socket.onopen = ((JSObject _) {
    if (completer.isCompleted) return;
    completer.complete(BrowserWebSocketEndpoint._(socket));
  }).toJS;
  socket.onerror = ((JSObject _) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Could not connect to $url'));
    }
  }).toJS;
  return completer.future;
}
