import 'dart:async';

import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

World _host() {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  return w;
}

World _client() {
  final w = World(width: 12, height: 12);
  registerCoreComponents(w);
  return w;
}

void main() {
  late World world;

  setUp(() => world = _host());

  /// Connects a client and runs the network for a few ticks.
  ({ClientSession client, LoopbackLink link}) connect(
    HostSession host, {
    String? token,
    String? name,
  }) {
    final link = LoopbackLink();
    final client = ClientSession(
      world: _client(),
      endpoint: link.b,
      token: token,
      name: name,
    );
    host.accept(link.a);
    return (client: client, link: link);
  }

  Future<void> run(
    HostSession host,
    List<LoopbackLink> links, [
    int ticks = 5,
  ]) async {
    for (var i = 0; i < ticks; i++) {
      world.step(0.05);
      host.afterStep();
      for (final l in links) {
        l.advance();
      }
      await Future<void>.delayed(Duration.zero);
    }
  }

  test(
    'without authenticate nothing changes: a client is admitted at once',
    () async {
      final host = HostSession(world: world, teams: ['red']);
      final c = connect(host);
      await run(host, [c.link]);
      expect(c.client.team, 'red');
      expect(host.pendingCount, 0);
    },
  );

  test(
    'a good token is admitted with its name; the check sees token and name',
    () async {
      String? seenToken, seenName;
      final host = HostSession(
        world: world,
        teams: ['red'],
        authenticate: (t, n) {
          seenToken = t;
          seenName = n;
          return t == 'secret';
        },
      );
      final c = connect(host, token: 'secret', name: 'Ada');
      expect(
        host.players,
        isEmpty,
        reason: 'no slot before the token is checked',
      );
      await run(host, [c.link]);
      expect(c.client.team, 'red');
      expect((seenToken, seenName), ('secret', 'Ada'));
      expect(host.players.values.single.name, 'Ada');
    },
  );

  test(
    'a wrong or missing token is denied, closed and never gets a team or state',
    () async {
      final host = HostSession(
        world: world,
        teams: ['red'],
        authenticate: (t, n) => t == 'secret',
      );
      final bad = connect(host, token: 'nope');
      await run(host, [bad.link]);
      expect(bad.client.denied, isTrue);
      expect(bad.client.team, isNull);
      expect(bad.client.connected, isFalse);
      expect(host.players, isEmpty);

      final silent = connect(host);
      await run(host, [silent.link]);
      expect(
        silent.client.team,
        isNull,
        reason: 'a connection that never says hello gets nothing',
      );
      expect(host.pendingCount, 1);
    },
  );

  test(
    'a connection that never authenticates is dropped after the timeout',
    () async {
      final host = HostSession(
        world: world,
        teams: ['red'],
        authenticate: (t, n) => true,
        authTimeoutTicks: 10,
      );
      final silent = connect(host);
      await run(host, [silent.link], 5);
      expect(host.pendingCount, 1);
      await run(host, [silent.link], 10);
      expect(host.pendingCount, 0);
      expect(silent.client.denied, isTrue);
    },
  );

  test('an async check works, and a throwing check counts as denied', () async {
    final host = HostSession(
      world: world,
      teams: ['red', 'blue'],
      authenticate: (t, n) async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        if (t == 'boom') throw StateError('database down');
        return t == 'ok';
      },
    );
    final good = connect(host, token: 'ok');
    final boom = connect(host, token: 'boom');
    for (var i = 0; i < 10; i++) {
      await run(host, [good.link, boom.link], 1);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(good.client.team, 'red');
    expect(boom.client.denied, isTrue);
  });

  test(
    'an authenticated player still cannot order another team\'s units',
    () async {
      final enemy = world.spawn();
      world.storeOf<Team>().set(enemy, Team('blue'));
      world.storeOf<GridPosition>().set(enemy, GridPosition(5, 5));
      final host = HostSession(
        world: world,
        teams: ['red', 'blue'],
        authenticate: (t, n) => t == 'ok',
      );
      final c = connect(host, token: 'ok');
      await run(host, [c.link]);
      final rejected = <String>[];
      c.client.onRejected = (u, r) => rejected.add(r);
      c.client.sendOrder(enemy, const MoveOrder(6, 5));
      await run(host, [c.link]);
      expect(rejected, ['not your unit']);
    },
  );
}
