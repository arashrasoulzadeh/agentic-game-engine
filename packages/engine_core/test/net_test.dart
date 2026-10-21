import 'package:engine_core/engine_core.dart';
import 'package:test/test.dart';

const _dt = 1 / 60;

/// A deterministic mini-game: each player (id == entity id) walks along x at the
/// speed their input asks for.
World _newWorld({int players = 2}) {
  final w = World(width: 1000, height: 100);
  registerCoreComponents(w);
  w.addSystem(MovementSystem());
  for (var i = 0; i < players; i++) {
    final e = w.spawn();
    w.storeOf<Position>().set(e, Position(0, 0));
    w.storeOf<Velocity>().set(e, Velocity(0, 0));
  }
  return w;
}

void _apply(World w, Map<int, Map<String, dynamic>> inputs) {
  for (final e in inputs.entries) {
    w.storeOf<Velocity>().get(e.key)!.x =
        ((e.value['dx'] as num?) ?? 0).toDouble() * 60;
  }
}

double _x(World w, int e) => w.storeOf<Position>().get(e)!.x;

void main() {
  group('LoopbackLink', () {
    test('delivers after the latency, not before, in order', () {
      final link = LoopbackLink(latencyTicks: 3);
      final got = <int>[];
      link.b.onMessage = (m) => got.add(m['n'] as int);
      link.a.send({'n': 1});
      link.a.send({'n': 2});
      link.advance();
      link.advance();
      expect(got, isEmpty);
      link.advance();
      expect(got, [1, 2]);
      expect(link.inFlight, 0);
    });

    test('is two-way and delivers copies, not shared objects', () {
      final link = LoopbackLink();
      final payload = {
        'list': [1],
      };
      Map<String, dynamic>? seenByA;
      link.a.onMessage = (m) => seenByA = m;
      link.b.send(payload);
      (payload['list']! as List).add(2);
      link.advance();
      expect(seenByA!['list'], [1]);
    });

    test('drops are seeded: the same seed loses the same packets', () {
      List<int> run(int seed) {
        final link = LoopbackLink(dropRate: 0.5, seed: seed);
        final got = <int>[];
        link.b.onMessage = (m) => got.add(m['n'] as int);
        for (var i = 0; i < 40; i++) {
          link.a.send({'n': i});
        }
        link.advance();
        expect(link.dropped, 40 - got.length);
        return got;
      }

      expect(run(7), run(7));
      expect(run(7), isNot(run(8)));
      expect(run(7).length, inInclusiveRange(8, 32));
    });

    test('jitter can reorder messages', () {
      final link = LoopbackLink(latencyTicks: 1, jitterTicks: 5, seed: 3);
      final got = <int>[];
      link.b.onMessage = (m) => got.add(m['n'] as int);
      for (var i = 0; i < 30; i++) {
        link.a.send({'n': i});
      }
      for (var i = 0; i < 10; i++) {
        link.advance();
      }
      expect(got.length, 30);
      expect(got, isNot(orderedEquals(List.generate(30, (i) => i))));
    });
  });

  group('RollbackSession', () {
    RollbackSession session(World w) =>
        RollbackSession(world: w, applyInputs: _apply, fixedDt: _dt);

    test('predicts a remote player repeats their last input', () {
      final w = _newWorld();
      final s = session(w);
      s.addInput(1, 0, {'dx': 1});
      for (var i = 0; i < 5; i++) {
        s.advance([0, 1]);
      }
      expect(s.inputFor(1, 4), {'dx': 1});
      expect(_x(w, 1), closeTo(5, 1e-9));
      expect(s.inputFor(0, 2), isEmpty);
    });

    test('a correct prediction needs no rollback', () {
      final w = _newWorld();
      final s = session(w);
      s.addInput(1, 0, {'dx': 1});
      for (var i = 0; i < 5; i++) {
        s.advance([0, 1]);
      }
      expect(s.addInput(1, 3, {'dx': 1}), isTrue);
      expect(s.needsReconcile, isFalse);
      expect(s.reconcile([0, 1]), 0);
    });

    test(
      'a wrong prediction rolls back and replays to exactly the true result',
      () {
        // Truth: player 1 held right for ticks 0-2, then stopped from tick 3.
        final truth = _newWorld();
        final t = session(truth);
        for (var i = 0; i < 10; i++) {
          t.addInput(1, i, {'dx': i < 3 ? 1 : 0});
          t.advance([0, 1]);
        }

        final w = _newWorld();
        final s = session(w);
        s.addInput(1, 0, {'dx': 1});
        for (var i = 0; i < 10; i++) {
          s.advance([0, 1]);
        }
        expect(_x(w, 1), isNot(closeTo(_x(truth, 1), 1e-9)));

        for (var i = 3; i < 10; i++) {
          s.addInput(1, i, {'dx': 0});
        }
        expect(s.needsReconcile, isTrue);
        final replayed = s.reconcile([0, 1]);
        expect(replayed, 7);
        expect(w.tick, 10);
        expect(_x(w, 1), closeTo(_x(truth, 1), 1e-9));
        expect(s.resimulatedTicks, 7);
        expect(s.needsReconcile, isFalse);
      },
    );

    test('inputs older than the rollback window are counted and ignored', () {
      final w = _newWorld();
      final s = RollbackSession(
        world: w,
        applyInputs: _apply,
        fixedDt: _dt,
        maxRollbackTicks: 4,
      );
      for (var i = 0; i < 20; i++) {
        s.advance([0, 1]);
      }
      expect(s.addInput(1, 2, {'dx': 1}), isFalse);
      expect(s.lateInputs, 1);
      expect(s.needsReconcile, isFalse);
    });

    test(
      'correctState replays our inputs on top of an authoritative past state',
      () {
        final server = _newWorld();
        final srv = session(server);
        final client = _newWorld();
        final cl = session(client);
        for (var i = 0; i < 6; i++) {
          srv.addInput(0, i, {'dx': 1});
          srv.advance([0]);
        }
        final authoritativeAt3 = WorldSnapshot.capture(_replayTo(3));
        for (var i = 0; i < 6; i++) {
          cl.addInput(0, i, {'dx': 1});
          cl.advance([0]);
        }
        client.storeOf<Position>().get(0)!.x = 999; // client drifted
        final replayed = cl.correctState(authoritativeAt3, [0]);
        expect(replayed, 3);
        expect(client.tick, 6);
        expect(_x(client, 0), closeTo(_x(server, 0), 1e-9));
      },
    );

    test('correctState ahead of the client just jumps to it', () {
      final w = _newWorld();
      final s = session(w);
      final ahead = _replayTo(8);
      expect(s.correctState(WorldSnapshot.capture(ahead), [0]), 0);
      expect(w.tick, 8);
    });
  });

  group('PositionHistory (lag compensation)', () {
    PositionHistory recorded() {
      final w = _newWorld(players: 1);
      final h = PositionHistory();
      for (var i = 0; i < 10; i++) {
        w.storeOf<Velocity>().get(0)!.x = 60;
        w.step(_dt);
        h.record(w);
      }
      return h;
    }

    test(
      'returns where the target was at a past tick, interpolating fractions',
      () {
        final h = recorded();
        expect(h.range, (1, 10));
        expect(h.positionAt(0, 5)!.x, closeTo(5, 1e-9));
        expect(h.positionAt(0, 5.5)!.x, closeTo(5.5, 1e-9));
      },
    );

    test('clamps outside the range and is null for an unknown entity', () {
      final h = recorded();
      expect(h.positionAt(0, 0)!.x, closeTo(1, 1e-9));
      expect(h.positionAt(0, 99)!.x, closeTo(10, 1e-9));
      expect(h.positionAt(42, 5), isNull);
      expect(PositionHistory().range, isNull);
    });

    test('rewinding for latency makes a shot at the old position count', () {
      final h = recorded();
      final tickNow = 10.0;
      final rewind = PositionHistory.rewindTick(
        currentTick: tickNow,
        latencyTicks: 4,
        interpolationTicks: 1,
      );
      expect(rewind, 5);
      final seenByShooter = h.rewind(rewind)[0]!;
      final onServerNow = h.positionAt(0, tickNow)!;
      expect(onServerNow.x - seenByShooter.x, closeTo(5, 1e-9));
    });

    test('ticksFor converts a duration', () {
      expect(
        PositionHistory.ticksFor(const Duration(milliseconds: 100), 1 / 60),
        closeTo(6, 1e-9),
      );
    });

    test(
      'a tick recorded twice keeps the later value; capacity drops the oldest',
      () {
        final w = _newWorld(players: 1);
        final h = PositionHistory(capacity: 3);
        w.storeOf<Position>().get(0)!.x = 1;
        h.record(w);
        w.storeOf<Position>().get(0)!.x = 2;
        h.record(w);
        expect(h.positionAt(0, 0)!.x, 2);
        for (var i = 0; i < 5; i++) {
          w.step(_dt);
          h.record(w);
        }
        final range = h.range!;
        expect(range.$2 - range.$1, 2);
        h.clear();
        expect(h.range, isNull);
      },
    );

    test('recordSnapshot reads positions from a snapshot', () {
      final h = PositionHistory();
      h.recordSnapshot(
        WorldSnapshot(4, {
          7: {
            'position': {'x': 3.0, 'y': 1.0},
          },
          8: {
            'velocity': {'x': 1.0, 'y': 1.0},
          },
        }),
      );
      expect(h.positionAt(7, 4)!.y, 1);
      expect(h.positionAt(8, 4), isNull);
    });
  });

  group('state sync', () {
    test('a new client gets a snapshot, then deltas of only what changed', () {
      final server = _newWorld(players: 3);
      final client = World(width: 1000, height: 100);
      registerCoreComponents(client);
      final link = LoopbackLink();
      final sync = StateSyncServer(world: server)..addClient(1, link.a.send);
      final cs = StateSyncClient(world: client, send: link.b.send);
      link.a.onMessage = (m) => sync.handle(1, m);
      link.b.onMessage = cs.receive;

      server.step(_dt);
      sync.broadcast();
      link.advance();
      link.advance();
      expect(sync.fullSnapshotsSent, 1);
      expect(client.entities.count, 3);

      server.storeOf<Position>().get(2)!.x = 77;
      server.step(_dt);
      sync.broadcast();
      expect(sync.deltasSent, 1);
      link.advance();
      link.advance();
      expect(_x(client, 2), closeTo(77, 1));
      expect(client.entities.count, 3);
    });

    test('removals and spawns replicate', () {
      final server = _newWorld(players: 2);
      final client = World(width: 1000, height: 100);
      registerCoreComponents(client);
      final link = LoopbackLink();
      final sync = StateSyncServer(world: server)..addClient(1, link.a.send);
      final cs = StateSyncClient(world: client, send: link.b.send);
      link.a.onMessage = (m) => sync.handle(1, m);
      link.b.onMessage = cs.receive;
      void tick() {
        server.step(_dt);
        sync.broadcast();
        link.advance();
        link.advance();
      }

      tick();
      server.destroy(0);
      final fresh = server.spawn();
      server.storeOf<Position>().set(fresh, Position(5, 5));
      tick();
      tick();
      expect(client.entities.isAlive(1), isTrue);
      expect(client.entities.isAlive(fresh), isTrue);
      expect(
        WorldSnapshot.capture(client).entities,
        WorldSnapshot.capture(server).entities,
      );
    });

    test('stays consistent over a lossy, laggy, reordering link', () {
      final server = _newWorld(players: 4);
      final client = World(width: 1000, height: 100);
      registerCoreComponents(client);
      final toClient = LoopbackLink(
        latencyTicks: 2,
        jitterTicks: 3,
        dropRate: 0.3,
        seed: 11,
      );
      final toServer = LoopbackLink(
        latencyTicks: 2,
        jitterTicks: 3,
        dropRate: 0.3,
        seed: 12,
      );
      final sync = StateSyncServer(world: server)
        ..addClient(1, toClient.a.send);
      final cs = StateSyncClient(world: client, send: toServer.a.send);
      toClient.b.onMessage = cs.receive;
      toServer.b.onMessage = (m) => sync.handle(1, m);

      for (var i = 0; i < 200; i++) {
        for (var p = 0; p < 4; p++) {
          server.storeOf<Velocity>().get(p)!.x =
              (i % 17 < 8 ? 1 : -1) * 30.0 * (p + 1);
        }
        server.step(_dt);
        sync.broadcast();
        toClient.advance();
        toServer.advance();
      }
      // Let the link drain, with the server stopped.
      for (var i = 0; i < 40; i++) {
        sync.broadcast();
        toClient.advance();
        toServer.advance();
      }
      expect(toClient.dropped, greaterThan(0));
      expect(
        WorldSnapshot.capture(client).entities,
        WorldSnapshot.capture(server).entities,
      );
      expect(client.tick, server.tick);
      expect(sync.deltasSent, greaterThan(sync.fullSnapshotsSent));
    });

    test('an out-of-order older packet cannot rewind the client', () {
      final client = World(width: 10, height: 10);
      registerCoreComponents(client);
      final sent = <Map<String, dynamic>>[];
      final cs = StateSyncClient(world: client, send: sent.add);
      Map<String, dynamic> snap(int tick, double x) => {
        'type': 'snapshot',
        'state': WorldSnapshot(tick, {
          0: {
            'position': {'x': x, 'y': 0.0},
          },
        }).toJson(),
      };
      cs.receive(snap(10, 10));
      cs.receive(snap(5, 5));
      expect(cs.latestTick, 10);
      expect(_x(client, 0), 10);
      expect(sent.single, {'type': 'ack', 'tick': 10});
    });

    test(
      'a delta against a baseline the client never held is counted and ignored',
      () {
        final client = World(width: 10, height: 10);
        registerCoreComponents(client);
        final cs = StateSyncClient(world: client, send: (_) {});
        cs.receive({
          'type': 'delta',
          'delta': WorldDelta(
            baseTick: 3,
            tick: 4,
            changed: {},
            removed: [],
          ).toJson(),
        });
        expect(cs.unusableDeltas, 1);
        expect(cs.latestTick, isNull);
        cs.receive({'type': 'nonsense'});
        expect(cs.latestTick, isNull);
      },
    );

    test('inputs reach the server; a bogus ack is ignored', () {
      final server = _newWorld(players: 1);
      final sync = StateSyncServer(world: server);
      final got = <Map<String, dynamic>>[];
      sync.onInput = (c, m) => got.add({'client': c, ...m});
      final cs = StateSyncClient(
        world: _newWorld(players: 1),
        send: (m) => sync.handle(5, m),
      );
      cs.sendInput(0, 12, {'dx': 1});
      expect(got.single['client'], 5);
      expect(got.single['tick'], 12);
      sync.handle(5, {'type': 'ack', 'tick': 9999});
      sync.addClient(5, (_) {});
      sync.broadcast();
      expect(sync.fullSnapshotsSent, 1);
      sync.removeClient(5);
    });

    test('client positions history supports interpolating remote entities', () {
      final client = World(width: 10, height: 10);
      registerCoreComponents(client);
      final cs = StateSyncClient(world: client, send: (_) {});
      for (final (tick, x) in [(1, 0.0), (3, 10.0)]) {
        cs.receive({
          'type': 'snapshot',
          'state': WorldSnapshot(tick, {
            0: {
              'position': {'x': x, 'y': 0.0},
            },
          }).toJson(),
        });
      }
      expect(cs.history.positionAt(0, 2)!.x, closeTo(5, 1e-9));
    });
  });

  group('end to end: client prediction + rollback + server authority', () {
    test(
      'a predicting client converges with the server despite loss and lag',
      () {
        final server = _newWorld();
        final client = _newWorld();
        final srvSession = RollbackSession(
          world: server,
          applyInputs: _apply,
          fixedDt: _dt,
        );
        final cliSession = RollbackSession(
          world: client,
          applyInputs: _apply,
          fixedDt: _dt,
        );
        final upstream = LoopbackLink(latencyTicks: 3, dropRate: 0.15, seed: 5);
        final downstream = LoopbackLink(
          latencyTicks: 3,
          dropRate: 0.15,
          seed: 6,
        );

        // Server keeps player 0's input from the client; the client learns player 1's from the server.
        upstream.b.onMessage = (m) => srvSession.addInput(
          0,
          m['tick'] as int,
          (m['input'] as Map).cast(),
        );
        downstream.b.onMessage = (m) => cliSession.addInput(
          1,
          m['tick'] as int,
          (m['input'] as Map).cast(),
        );

        Map<String, dynamic> inputFor(int player, int t) => {
          'dx': ((t ~/ 7) + player) % 3 - 1,
        };

        for (var t = 0; t < 120; t++) {
          final mine = inputFor(0, t);
          cliSession.addInput(0, t, mine);
          upstream.a.send({'tick': t, 'input': mine});
          final theirs = inputFor(1, t);
          srvSession.addInput(1, t, theirs);
          downstream.a.send({'tick': t, 'input': theirs});

          cliSession.advance([0, 1]);
          srvSession.advance([0, 1]);
          upstream.advance();
          downstream.advance();
          cliSession.reconcile([0, 1]);
        }
        expect(
          cliSession.resimulatedTicks,
          greaterThan(0),
          reason: 'predictions were wrong at least once',
        );

        // Authoritative correction closes whatever loss left behind.
        final authoritative = WorldSnapshot.capture(server);
        cliSession.correctState(authoritative, [0, 1]);
        expect(client.tick, server.tick);
        expect(_x(client, 0), closeTo(_x(server, 0), 1e-9));
        expect(_x(client, 1), closeTo(_x(server, 1), 1e-9));
      },
    );
  });
}

World _replayTo(int ticks) {
  final w = _newWorld();
  final s = RollbackSession(world: w, applyInputs: _apply, fixedDt: _dt);
  for (var i = 0; i < ticks; i++) {
    s.addInput(0, i, {'dx': 1});
    s.advance([0]);
  }
  return w;
}
