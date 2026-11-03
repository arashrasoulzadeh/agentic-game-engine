import 'dart:convert';

import '../ecs/deterministic_random.dart';
import 'net_endpoint.dart';

/// One end of a [LoopbackLink]: send JSON messages, receive them via [onMessage].
class LinkEndpoint implements NetEndpoint {
  LinkEndpoint._(this._link, this._index);

  final LoopbackLink _link;
  final int _index;

  @override
  void Function(Map<String, dynamic> message)? onMessage;

  @override
  void Function()? onClose;

  bool _closed = false;

  /// Queues [message] for the other end (subject to the link's latency and loss).
  /// Ignored once either end has closed.
  @override
  void send(Map<String, dynamic> message) {
    if (_closed || _link._endpointAt(1 - _index)._closed) return;
    _link._send(_index, message);
  }

  /// Ends the connection for both sides and notifies each via [onClose].
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    onClose?.call();
    final peer = _link._endpointAt(1 - _index);
    if (!peer._closed) {
      peer._closed = true;
      peer.onClose?.call();
    }
  }
}

/// An in-memory, tick-driven link between two endpoints with fixed latency,
/// optional jitter and packet loss -- a deterministic stand-in for a real socket.
///
/// It exists so networking logic (sync, rollback, prediction) can be tested
/// and replayed exactly: same seed, same drops. A real transport implements the
/// same two operations -- send a JSON map, receive JSON maps -- so the sync code
/// never depends on one. Messages are round-tripped through JSON on send, which
/// proves they are plain data and prevents the two sides sharing mutable objects.
class LoopbackLink {
  LoopbackLink({
    this.latencyTicks = 0,
    this.jitterTicks = 0,
    this.dropRate = 0,
    int seed = 1,
  }) : assert(latencyTicks >= 0 && jitterTicks >= 0),
       assert(dropRate >= 0 && dropRate <= 1),
       _random = DeterministicRandom(seed) {
    a = LinkEndpoint._(this, 0);
    b = LinkEndpoint._(this, 1);
  }

  final int latencyTicks;
  final int jitterTicks;
  final double dropRate;
  final DeterministicRandom _random;

  late final LinkEndpoint a;
  late final LinkEndpoint b;

  int _clock = 0;
  final List<_InFlight> _queue = [];
  int sent = 0;
  int dropped = 0;

  LinkEndpoint _endpointAt(int index) => index == 0 ? a : b;

  void _send(int from, Map<String, dynamic> message) {
    sent++;
    if (dropRate > 0 && _random.nextDouble() < dropRate) {
      dropped++;
      return;
    }
    final jitter = jitterTicks == 0 ? 0 : _random.nextInt(jitterTicks + 1);
    _queue.add(
      _InFlight(
        to: 1 - from,
        at: _clock + latencyTicks + jitter,
        message: (jsonDecode(jsonEncode(message)) as Map)
            .cast<String, dynamic>(),
      ),
    );
  }

  /// Advances the link one tick and delivers everything due, oldest first. With
  /// jitter, a later message can arrive before an earlier one (reordering),
  /// like UDP.
  void advance() {
    _clock++;
    final due = _queue.where((m) => m.at <= _clock).toList()
      ..sort((x, y) => x.at.compareTo(y.at));
    _queue.removeWhere((m) => m.at <= _clock);
    for (final m in due) {
      (m.to == 0 ? a : b).onMessage?.call(m.message);
    }
  }

  int get inFlight => _queue.length;
}

class _InFlight {
  _InFlight({required this.to, required this.at, required this.message});
  final int to;
  final int at;
  final Map<String, dynamic> message;
}
