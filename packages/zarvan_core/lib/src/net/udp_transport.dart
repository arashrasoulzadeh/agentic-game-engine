import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'net_endpoint.dart';
import 'net_frame.dart';

/// The largest datagram sent. A UDP packet over about 1,400 bytes is split by the network and any lost
/// fragment loses the whole message, so keep messages small on the internet (deltas, orders); the loopback
/// and a LAN take far more. 60,000 is the hard ceiling of the protocol.
const udpMaxMessageBytes = 60000;

const _control = '_udp';

/// A [NetEndpoint] over UDP datagrams to one peer: lower latency than a WebSocket because a lost packet is
/// not waited for. The sync layer is written for that (it sends full snapshots and acknowledged deltas), so a
/// dropped or reordered message is repaired by the next one.
///
/// UDP has no connection, so this adds the minimum: the first packet makes a peer known, a `bye` ends it at
/// once, and a peer silent for [idleTimeout] is considered gone (each side sends a keep-alive a third of the
/// way through the timeout while idle).
class UdpEndpoint implements NetEndpoint {
  UdpEndpoint._(
    this._send,
    this.idleTimeout, {
    required void Function() onDispose,
  }) : _onDispose = onDispose {
    _timer = Timer.periodic(idleTimeout ~/ 3, (_) => _tick());
  }

  final void Function(List<int> bytes) _send;
  final Duration idleTimeout;
  final void Function() _onDispose;
  late final Timer _timer;
  bool _isClosed = false;
  DateTime _heardAt = DateTime.now();
  DateTime _sentAt = DateTime.now();

  /// Datagrams dropped as malformed - for diagnostics and tests.
  int malformedFrames = 0;

  /// Messages refused because they exceeded [udpMaxMessageBytes].
  int oversized = 0;

  @override
  void Function(Map<String, dynamic> message)? onMessage;

  @override
  void Function()? onClose;

  void _tick() {
    final now = DateTime.now();
    if (now.difference(_heardAt) > idleTimeout) {
      close(notifyPeer: false);
    } else if (now.difference(_sentAt) > idleTimeout ~/ 3) {
      _raw({_control: 'ka'});
    }
  }

  void _raw(Map<String, dynamic> message) {
    _sentAt = DateTime.now();
    _send(utf8.encode(encodeNetFrame(message)));
  }

  /// Called with each datagram's text from this peer.
  void _receive(String data) {
    _heardAt = DateTime.now();
    final message = decodeNetFrame(data);
    if (message == null) {
      malformedFrames++;
      return;
    }
    switch (message[_control]) {
      case 'bye':
        close(notifyPeer: false);
        return;
      case 'ka' || 'open':
        return;
    }
    onMessage?.call(message);
  }

  @override
  void send(Map<String, dynamic> message) {
    if (_isClosed) return;
    final bytes = utf8.encode(encodeNetFrame(message));
    if (bytes.length > udpMaxMessageBytes) {
      oversized++;
      return;
    }
    _sentAt = DateTime.now();
    _send(bytes);
  }

  @override
  void close({bool notifyPeer = true}) {
    if (_isClosed) return;
    _isClosed = true;
    _timer.cancel();
    if (notifyPeer) _raw({_control: 'bye'});
    _onDispose();
    onClose?.call();
  }
}

/// Connects to a UDP host at [host]:[port]. UDP cannot fail to connect: the returned endpoint just starts
/// sending, and a host that is not there is noticed when it stays silent for [idleTimeout].
Future<NetEndpoint> connectUdp(
  String host,
  int port, {
  Duration idleTimeout = const Duration(seconds: 10),
}) async {
  final address = (await InternetAddress.lookup(host)).first;
  final socket = await RawDatagramSocket.bind(
    address.type == InternetAddressType.IPv6
        ? InternetAddress.anyIPv6
        : InternetAddress.anyIPv4,
    0,
  );
  late final UdpEndpoint endpoint;
  endpoint = UdpEndpoint._(
    (bytes) => socket.send(bytes, address, port),
    idleTimeout,
    onDispose: socket.close,
  );
  socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    Datagram? d;
    while ((d = socket.receive()) != null) {
      if (d!.address == address && d.port == port) {
        endpoint._receive(utf8.decode(d.data, allowMalformed: true));
      }
    }
  });
  // Introduce ourselves, so the host learns this peer exists before any game message is sent.
  endpoint._raw({_control: 'open'});
  return endpoint;
}

/// A UDP server. The first datagram from an address creates a [NetEndpoint] for it, handed to
/// [onConnection] - typically `hostSession.accept`; later datagrams from that address go to the same one.
class UdpListener {
  UdpListener._(this._socket, this._idleTimeout);

  final RawDatagramSocket _socket;
  final Duration _idleTimeout;
  final Map<String, UdpEndpoint> _peers = {};

  /// The port actually bound (useful when you asked for port 0).
  int get port => _socket.port;

  /// Peers currently known.
  int get peerCount => _peers.length;

  /// Starts listening on [host]:[port] (port 0 picks a free one).
  static Future<UdpListener> bind(
    void Function(NetEndpoint endpoint) onConnection, {
    Object host = '127.0.0.1',
    int port = 0,
    Duration idleTimeout = const Duration(seconds: 10),
  }) async {
    final socket = await RawDatagramSocket.bind(host, port);
    final listener = UdpListener._(socket, idleTimeout);
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? d;
      while ((d = socket.receive()) != null) {
        listener._onDatagram(d!, onConnection);
      }
    });
    return listener;
  }

  void _onDatagram(Datagram d, void Function(NetEndpoint) onConnection) {
    final key = '${d.address.address}:${d.port}';
    var peer = _peers[key];
    final text = utf8.decode(d.data, allowMalformed: true);
    if (peer == null) {
      // A stray "bye" or keep-alive from a peer we already forgot must not resurrect it.
      final probe = decodeNetFrame(text);
      if (probe == null ||
          probe[_control] == 'bye' ||
          probe[_control] == 'ka') {
        return;
      }
      peer = UdpEndpoint._(
        (bytes) => _socket.send(bytes, d.address, d.port),
        _idleTimeout,
        onDispose: () => _peers.remove(key),
      );
      _peers[key] = peer;
      onConnection(peer);
    }
    peer._receive(text);
  }

  /// Stops listening and closes every peer.
  Future<void> close() async {
    for (final p in _peers.values.toList()) {
      p.close();
    }
    _socket.close();
  }
}
