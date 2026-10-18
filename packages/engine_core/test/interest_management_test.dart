import 'dart:convert';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

const _dt = 1 / 20;

/// Entities 0..n-1 spaced 100 units apart along x, so "near x=0" is a small prefix.
World _server(int n) {
  final w = World(width: 5000, height: 100);
  registerCoreComponents(w);
  for (var i = 0; i < n; i++) {
    final e = w.spawn();
    w.storeOf<Position>().set(e, Position(i * 100.0, 0));
  }
  return w;
}

class _Rig {
  _Rig(this.server, {InterestFilter Function()? interest, this.clientId = 1}) {
    client = World(width: 5000, height: 100);
    registerCoreComponents(client);
    sync = StateSyncServer(world: server)..addClient(clientId, link.a.send, interest: interest);
    cs = StateSyncClient(world: client, send: link.b.send);
    link.a.onMessage = (m) => sync.handle(clientId, m);
    link.b.onMessage = cs.receive;
  }

  final World server;
  final int clientId;
  late final World client;
  late final StateSyncServer sync;
  late final StateSyncClient cs;
  final link = LoopbackLink();

  void tick() {
    server.step(_dt);
    sync.broadcast();
    link.advance();
    link.advance();
  }
}

void main() {
  test('a client with a nearby rule only receives entities near its viewpoint', () {
    final server = _server(20);
    final r = _Rig(server,
        interest: nearbyInterest(center: () => (x: 0, y: 0), radius: 250));
    r.tick();
    expect(r.client.entities.all.toSet(), {0, 1, 2}, reason: 'x = 0, 100, 200 are within 250');
  });

  test('entities leaving the view are removed on the client; entering ones appear', () {
    final server = _server(20);
    var viewX = 0.0;
    final r = _Rig(server, interest: nearbyInterest(center: () => (x: viewX, y: 0), radius: 150));
    r.tick();
    expect(r.client.entities.all.toSet(), {0, 1});

    viewX = 1000;
    r.tick();
    r.tick();
    expect(r.client.entities.all.toSet(), {9, 10, 11}, reason: 'x = 900..1100; the old ones are gone');
  });

  test('a delta tells the client about changes only inside its view', () {
    final server = _server(20);
    final r = _Rig(server, interest: nearbyInterest(center: () => (x: 0, y: 0), radius: 250));
    r.tick();
    r.tick();
    final before = r.sync.deltasSent;

    server.storeOf<Position>().get(15)!.x = 1501; // far outside the view
    r.tick();
    expect(r.sync.deltasSent, before + 1);
    expect(r.client.entities.isAlive(15), isFalse);
    expect(r.client.entities.all.toSet(), {0, 1, 2});

    server.storeOf<Position>().get(1)!.x = 111; // inside
    r.tick();
    expect(r.client.storeOf<Position>().get(1)!.x, closeTo(111, 1));
  });

  test('an entity with no position (global state) is always sent', () {
    final server = _server(5);
    final global = server.spawn();
    server.storeOf<Treasury>().set(global, Treasury('red', amounts: {'gold': 5}));
    final r = _Rig(server, interest: nearbyInterest(center: () => (x: 0, y: 0), radius: 10));
    r.tick();
    expect(r.client.entities.isAlive(global), isTrue);
    expect(r.client.entities.isAlive(4), isFalse);
  });

  test('always keeps listed ids visible however far away', () {
    final server = _server(20);
    final r = _Rig(server,
        interest: nearbyInterest(center: () => (x: 0, y: 0), radius: 10, always: () => [19]));
    r.tick();
    expect(r.client.entities.all.toSet(), {0, 19});
  });

  test('filtering sends fewer bytes than the full world, and an unfiltered client is unchanged', () {
    final server = _server(60);
    final filtered = _Rig(server, interest: nearbyInterest(center: () => (x: 0, y: 0), radius: 250));
    final everything = _Rig(server, clientId: 2);
    final sizes = <String, int>{};
    // Measure what each server would send for the first snapshot.
    final f = <Map<String, dynamic>>[];
    final a = <Map<String, dynamic>>[];
    final s1 = StateSyncServer(world: server)
      ..addClient(1, f.add, interest: nearbyInterest(center: () => (x: 0, y: 0), radius: 250))
      ..addClient(2, a.add);
    s1.broadcast();
    sizes['filtered'] = jsonEncode(f.single).length;
    sizes['all'] = jsonEncode(a.single).length;
    expect(sizes['filtered']!, lessThan(sizes['all']! ~/ 5));

    everything.tick();
    expect(everything.client.entities.count, 60);
    filtered.tick();
    expect(filtered.client.entities.count, 3);
  });

  test('removeClient drops the interest bookkeeping (no growth for departed clients)', () {
    final server = _server(5);
    final sent = <Map<String, dynamic>>[];
    final sync = StateSyncServer(world: server)
      ..addClient(1, sent.add, interest: nearbyInterest(center: () => (x: 0, y: 0), radius: 50));
    sync.broadcast();
    sync.removeClient(1);
    sent.clear();
    sync.broadcast();
    expect(sent, isEmpty);
  });
}
