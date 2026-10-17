/// One end of a connection that carries JSON messages. The only thing the sync and
/// session code needs from a transport, so a WebSocket, the in-memory
/// `LoopbackLink` (tests, replays) or a future WebRTC data channel are
/// interchangeable.
///
/// Messages are plain JSON maps; a transport serializes them however it likes but
/// must deliver an equal map to the other side. Delivery may be delayed, dropped
/// or (for unreliable transports) reordered - the sync layer is written for that.
abstract class NetEndpoint {
  /// Sends [message] to the peer.
  void send(Map<String, dynamic> message);

  /// Called for each message received.
  void Function(Map<String, dynamic> message)? onMessage;

  /// Called once when the connection ends, whichever side ended it.
  void Function()? onClose;

  /// Closes the connection. Idempotent.
  void close();
}
