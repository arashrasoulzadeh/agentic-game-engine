import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

void main() {
  late LobbyServer lobby;
  setUp(() => lobby = LobbyServer(maxRooms: 3));

  /// A connected client; [replies] collects what the lobby sends back.
  ({LinkEndpoint end, List<Map<String, dynamic>> replies, LoopbackLink link})
  client() {
    final link = LoopbackLink();
    final replies = <Map<String, dynamic>>[];
    link.b.onMessage = replies.add;
    lobby.accept(link.a);
    return (end: link.b, replies: replies, link: link);
  }

  Map<String, dynamic> room(
    String name, {
    int max = 4,
    String url = 'wss://h:1',
  }) => {'type': 'create', 'name': name, 'url': url, 'maxPlayers': max};

  test('a host announces a room, a player lists it', () {
    final host = client();
    host.end.send(room('Duel', max: 2));
    host.link.advance();
    host.link.advance();
    expect(host.replies.single['type'], 'created');

    final player = client();
    player.end.send({'type': 'list'});
    player.link.advance();
    player.link.advance();
    final rooms = (player.replies.single['rooms'] as List)
        .cast<Map<String, dynamic>>();
    expect(rooms.single['name'], 'Duel');
    expect(rooms.single['url'], 'wss://h:1');
    expect(LobbyRoom.fromJson(rooms.single).maxPlayers, 2);
  });

  test('full rooms are not listed; update reopens them', () {
    final host = client();
    host.end.send(room('Duel', max: 2));
    host.link.advance();
    host.link.advance();
    final id = host.replies.single['id'];
    host.end.send({'type': 'update', 'id': id, 'players': 2});
    host.link.advance();

    final p = client();
    List listed() {
      p.replies.clear();
      p.end.send({'type': 'list'});
      p.link.advance();
      p.link.advance();
      return p.replies.single['rooms'] as List;
    }

    expect(listed(), isEmpty);
    host.end.send({'type': 'update', 'id': id, 'players': 1});
    host.link.advance();
    expect(listed(), hasLength(1));
  });

  test(
    'a room disappears when its host\'s connection ends, or when it closes it',
    () {
      final a = client();
      a.end.send(room('A'));
      a.link.advance();
      final b = client();
      b.end.send(room('B'));
      b.link.advance();
      expect(lobby.rooms.map((r) => r.name), ['A', 'B']);

      a.end.close();
      expect(lobby.rooms.map((r) => r.name), [
        'B',
      ], reason: 'a crashed host never lingers');

      b.link.advance();
      b.link.advance();
      final id = b.replies.single['id'];
      b.end.send({'type': 'close', 'id': id});
      b.link.advance();
      expect(lobby.rooms, isEmpty);
    },
  );

  test('only the owner can update or close a room', () {
    final host = client();
    host.end.send(room('Mine'));
    host.link.advance();
    host.link.advance();
    final id = host.replies.single['id'];

    final intruder = client();
    intruder.end.send({'type': 'update', 'id': id, 'players': 4});
    intruder.end.send({'type': 'close', 'id': id});
    intruder.link.advance();
    expect(lobby.rooms.single.players, 0);
    expect(lobby.rooms, hasLength(1));
  });

  test('malformed or excessive requests are refused', () {
    final c = client();
    for (final bad in [
      {'type': 'create', 'name': '', 'url': 'u', 'maxPlayers': 2},
      {'type': 'create', 'name': 'x', 'url': 'u', 'maxPlayers': 0},
      {'type': 'create', 'name': 'x', 'url': 'u', 'maxPlayers': 'many'},
      {'type': 'create', 'name': 'n' * 81, 'url': 'u', 'maxPlayers': 2},
      {
        'type': 'create',
        'name': 'x',
        'url': 'u',
        'maxPlayers': 2,
        'info': 'text',
      },
      {
        'type': 'create',
        'name': 'x',
        'url': 'u',
        'maxPlayers': 2,
        'info': {'k': 'v' * 2000},
      },
    ]) {
      c.end.send(bad);
    }
    for (var i = 0; i < 4; i++) {
      c.link.advance();
    }
    expect(c.replies.every((r) => r['type'] == 'refused'), isTrue);
    expect(c.replies, hasLength(6));
    expect(lobby.rooms, isEmpty);

    c.replies.clear();
    c.end.send(room('one'));
    c.end.send(room('two'));
    for (var i = 0; i < 4; i++) {
      c.link.advance();
    }
    expect(c.replies.map((r) => r['type']), [
      'created',
      'refused',
    ], reason: 'one room per connection by default');
  });

  test('the lobby caps the total number of rooms', () {
    final clients = [for (var i = 0; i < 4; i++) client()];
    for (var i = 0; i < 4; i++) {
      clients[i].end.send(room('R$i'));
      clients[i].link.advance();
      clients[i].link.advance();
    }
    expect(lobby.rooms, hasLength(3));
    expect(clients.last.replies.single['reason'], 'too many rooms');
  });
}
