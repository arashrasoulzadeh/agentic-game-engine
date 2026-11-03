import 'dart:convert';

import 'net_endpoint.dart';

/// A game room a host has announced: where to connect, who is in it and how many it takes.
class LobbyRoom {
  LobbyRoom({
    required this.id,
    required this.name,
    required this.url,
    required this.maxPlayers,
    this.players = 0,
    this.info = const {},
  });

  final int id;
  final String name;

  /// Where players connect (`wss://game.example.com:4040`, or a UDP `host:port`); the lobby only passes it on.
  final String url;
  final int maxPlayers;
  int players;

  /// Anything else the game wants to show in a room list (map name, mode, version).
  final Map<String, dynamic> info;

  bool get isFull => players >= maxPlayers;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'maxPlayers': maxPlayers,
    'players': players,
    if (info.isNotEmpty) 'info': info,
  };

  factory LobbyRoom.fromJson(Map<String, dynamic> json) => LobbyRoom(
    id: (json['id'] as num).toInt(),
    name: json['name'] as String,
    url: json['url'] as String,
    maxPlayers: (json['maxPlayers'] as num).toInt(),
    players: (json['players'] as num?)?.toInt() ?? 0,
    info: ((json['info'] as Map?) ?? const {}).cast<String, dynamic>(),
  );
}

/// A room list service: game hosts announce their rooms, players ask what is open and then connect to a room's
/// `url` themselves. It is the "find a game" half of matchmaking. It does **not** relay game traffic or punch
/// through NAT, so hosts must be reachable (a server, or a forwarded port); pair it with a relay if they are not.
///
/// Every connection speaks JSON over any [NetEndpoint], so it runs on the same WebSocket/UDP listeners as a game
/// host. Messages from a client: `list` (answered with `rooms`), `create` (`name`, `url`, `maxPlayers`, optional
/// `info`; answered with `created` and the room `id`), `update` (`players`), `close`. A room belongs to the
/// connection that created it and disappears when that connection ends, so a crashed host never lingers.
class LobbyServer {
  LobbyServer({this.maxRooms = 1000, this.maxRoomsPerConnection = 1});

  /// Rooms the lobby will list at once; further `create`s are refused.
  final int maxRooms;

  /// Rooms one connection may own.
  final int maxRoomsPerConnection;

  final Map<int, LobbyRoom> _rooms = {};
  final Map<int, NetEndpoint> _owners = {};
  int _nextId = 1;

  /// The rooms currently open, oldest first.
  List<LobbyRoom> get rooms => _rooms.values.toList();

  /// Takes a new connection (hand this to a listener's `onConnection`).
  void accept(NetEndpoint endpoint) {
    endpoint.onMessage = (m) => _handle(endpoint, m);
    endpoint.onClose = () {
      final mine = [
        for (final e in _owners.entries)
          if (identical(e.value, endpoint)) e.key,
      ];
      for (final id in mine) {
        _rooms.remove(id);
        _owners.remove(id);
      }
    };
  }

  void _handle(NetEndpoint from, Map<String, dynamic> m) {
    switch (m['type']) {
      case 'list':
        from.send({
          'type': 'rooms',
          'rooms': [
            for (final r in _rooms.values)
              if (!r.isFull) r.toJson(),
          ],
        });
      case 'create':
        _create(from, m);
      case 'update':
        final room = _ownedBy(from, m['id']);
        final players = m['players'];
        if (room != null && players is int && players >= 0)
          room.players = players;
      case 'close':
        final room = _ownedBy(from, m['id']);
        if (room != null) {
          _rooms.remove(room.id);
          _owners.remove(room.id);
        }
    }
  }

  void _create(NetEndpoint from, Map<String, dynamic> m) {
    final name = m['name'];
    final url = m['url'];
    final max = m['maxPlayers'];
    final owned = _owners.values.where((e) => identical(e, from)).length;
    if (name is! String ||
        url is! String ||
        max is! int ||
        max < 1 ||
        name.isEmpty ||
        name.length > 80 ||
        url.length > 300 ||
        (m['info'] != null &&
            (m['info'] is! Map || jsonEncode(m['info']).length > 1000))) {
      from.send({'type': 'refused', 'reason': 'malformed room'});
      return;
    }
    if (_rooms.length >= maxRooms || owned >= maxRoomsPerConnection) {
      from.send({'type': 'refused', 'reason': 'too many rooms'});
      return;
    }
    final room = LobbyRoom(
      id: _nextId++,
      name: name,
      url: url,
      maxPlayers: max,
      players: (m['players'] as int?) ?? 0,
      info: ((m['info'] as Map?) ?? const {}).cast<String, dynamic>(),
    );
    _rooms[room.id] = room;
    _owners[room.id] = from;
    from.send({'type': 'created', 'id': room.id});
  }

  LobbyRoom? _ownedBy(NetEndpoint who, Object? id) {
    if (id is! int) return null;
    final owner = _owners[id];
    return owner != null && identical(owner, who) ? _rooms[id] : null;
  }
}
