import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

class _Clock {
  DateTime now = DateTime.utc(2026, 1, 1, 12);
  DateTime call() => now;
}

IdleController _newGame() {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerIdleComponents(w);
  w.storeOf<BigTreasury>().set(
    w.spawn(),
    BigTreasury(amounts: {'coins': n('100')}),
  );
  w.storeOf<IdleModifiers>().set(w.spawn(), IdleModifiers());
  w.storeOf<IdleStats>().set(w.spawn(), IdleStats());
  w.storeOf<Generator>().set(
    w.spawn(),
    Generator(
      id: 'g',
      cost: GeometricCost(base: n('10'), growth: 1.1),
      output: {'coins': n('2')},
    ),
  );
  w.addSystem(IdleSystem());
  return IdleController(world: w);
}

void main() {
  late _Clock clock;
  late MemorySaveStore store;
  setUp(() {
    clock = _Clock();
    store = MemorySaveStore();
  });

  IdleSession session(
    IdleController c, {
    SaveMigrator? migrator,
    OfflineConfig offline = const OfflineConfig(),
  }) => IdleSession(
    controller: c,
    store: store,
    clock: clock.call,
    migrator: migrator,
    offline: offline,
  );

  test('there is nothing to load on a first run', () {
    expect(session(_newGame()).load(), isNull);
  });

  test(
    'save then load restores the whole game exactly, including big numbers and stats',
    () {
      final a = _newGame();
      a.buy(a.generatorIds.first, count: 5);
      a.world.storeOf<IdleStats>().denseAt(0).credit({'coins': n('1e200')});
      a.tick(10);
      final s = session(a)..save();

      final b = _newGame();
      session(b).load();
      expect(b.wallet.of('coins').approxEquals(a.wallet.of('coins')), isTrue);
      expect(b.world.storeOf<Generator>().denseAt(0).owned, 5);
      expect(
        b.world
            .storeOf<IdleStats>()
            .denseAt(0)
            .lifetimeEarned['coins']!
            .approxEquals(n('1e200')),
        isTrue,
      );
      expect(b.wallet.rateOf('coins'), a.wallet.rateOf('coins'));
      expect(s.lastActiveAt, clock.now);
    },
  );

  test(
    'loading after time away pays the capped catch-up and credits the stats',
    () {
      final a = _newGame();
      a.buy(a.generatorIds.first, count: 1); // 2 coins/s
      session(a).save();

      clock.now = clock.now.add(const Duration(hours: 3));
      final b = _newGame();
      final summary = session(b).load()!;
      expect(summary.credit.credited, const Duration(hours: 3));
      expect(
        summary.gained['coins']!.approxEquals(n('21600')),
        isTrue,
        reason: '2/s x 10800 s',
      );
      expect(
        b.world
            .storeOf<IdleStats>()
            .denseAt(0)
            .lifetimeEarned['coins']!
            .approxEquals(n('21600')),
        isTrue,
      );

      final long = _newGame();
      clock.now = clock.now.add(const Duration(days: 5));
      expect(session(long).load()!.credit.capped, isTrue);
    },
  );

  test(
    'pause saves and stops the clock; resume pays the time away and restarts it',
    () {
      final c = _newGame();
      c.buy(c.generatorIds.first); // 2 coins/s
      final s = session(c);
      s.onPause();
      expect(store.value, isNotNull);

      clock.now = clock.now.add(const Duration(hours: 1));
      final before = c.wallet.of('coins');
      final summary = s.onResume()!;
      expect((c.wallet.of('coins') - before).approxEquals(n('7200')), isTrue);
      expect(summary.gained['coins']!.approxEquals(n('7200')), isTrue);
      c.stop();
    },
  );

  test(
    'leaving schedules a reminder for when the offline cap is reached; returning cancels it',
    () {
      final c = _newGame();
      final notifier = RecordingNotifier();
      final s = IdleSession(
        controller: c,
        store: store,
        clock: clock.call,
        offline: const OfflineConfig(cap: Duration(hours: 4)),
        notifier: notifier,
        returnMessage: 'full!',
      );
      s.onPause();
      expect(notifier.pending!.delay, const Duration(hours: 4));
      expect(notifier.pending!.message, 'full!');
      clock.now = clock.now.add(const Duration(hours: 1));
      s.onResume();
      expect(notifier.pending, isNull);
      c.stop();
    },
  );

  test(
    'doubleOffline pays the away earnings a second time and counts them in the stats',
    () {
      final c = _newGame();
      c.buy(c.generatorIds.first);
      final s = session(c)..onPause();
      clock.now = clock.now.add(const Duration(hours: 1));
      final summary = s.onResume()!;
      final before = c.wallet.of('coins');
      s.doubleOffline(summary);
      expect(c.wallet.of('coins'), before + summary.gained['coins']!);
      final stats = c.world.storeOf<IdleStats>().denseAt(0);
      expect(stats.lifetimeEarned['coins'], summary.gained['coins']! * n('2'));
      c.stop();
    },
  );

  test(
    'stepping the world tick by tick and catching up the same time give the same wallet',
    () {
      BigTreasury fresh() {
        final c = _newGame();
        c.buy(c.generatorIds.first, count: 5);
        return c.wallet;
      }

      final stepped = _newGame();
      stepped.buy(stepped.generatorIds.first, count: 5);
      for (var i = 0; i < 3600; i++) {
        stepped.world.step(1);
      }

      final bulk = fresh();
      final t0 = DateTime.utc(2026);
      OfflineProgress.catchUp(
        bulk,
        lastActiveAt: t0,
        now: t0.add(const Duration(hours: 1)),
      );
      expect(
        stepped.wallet.of('coins').approxEquals(bulk.of('coins')),
        isTrue,
        reason: '${stepped.wallet.of('coins')} vs ${bulk.of('coins')}',
      );
      stepped.stop();
    },
  );

  test('whileAway lets an auto-buyer change the rate during the absence', () {
    final c = _newGame();
    c.buy(c.generatorIds.first);
    var calls = 0;
    final s = IdleSession(
      controller: c,
      store: store,
      clock: clock.call,
      awaySlices: 4,
      whileAway: () {
        calls++;
        c.wallet.incomePerSecond['coins'] = c.wallet.rateOf('coins') * n('2');
      },
    )..onPause();
    final rate = c.wallet.rateOf('coins');
    clock.now = clock.now.add(const Duration(hours: 4));
    final before = c.wallet.of('coins');
    final summary = s.onResume()!;
    expect(calls, 3);
    // Slices of one hour at 1x, 2x, 4x, 8x the starting rate.
    final expected = rate * n('3600') * n('15');
    expect(summary.gained['coins']!.approxEquals(expected), isTrue);
    expect(c.wallet.of('coins').approxEquals(before + expected), isTrue);
    c.stop();
  });

  test('a very short absence earns and reports nothing', () {
    final c = _newGame();
    c.buy(c.generatorIds.first);
    final s = session(c)..onPause();
    clock.now = clock.now.add(const Duration(seconds: 5));
    expect(s.onResume(), isNull);
    c.stop();
  });

  test(
    'an old save is migrated; a newer one is refused and the game is left alone',
    () {
      final a = _newGame();
      session(a).save();
      final migrated = SaveMigrator(
        currentVersion: 2,
        migrations: {
          1: (s) => {...s, 'extra': true},
        },
      );
      final b = _newGame();
      session(b, migrator: migrated).load();
      expect(
        store.value!['saveVersion'],
        1,
        reason: 'the stored file is not rewritten by load',
      );

      store.value = {...store.value!, 'saveVersion': 9};
      final c = _newGame();
      final before = c.wallet.of('coins');
      expect(() => session(c).load(), throwsA(isA<SaveFormatException>()));
      expect(c.wallet.of('coins'), before);
    },
  );

  test(
    'export and import move a game between devices, and bad codes change nothing',
    () {
      final a = _newGame();
      a.buy(a.generatorIds.first, count: 3);
      final code = session(a).exportCode();
      expect(code, startsWith('GSAVE1.'));

      final b = _newGame();
      session(b).importCode(code);
      expect(b.world.storeOf<Generator>().denseAt(0).owned, 3);

      final c = _newGame();
      final before = c.wallet.of('coins');
      expect(
        () => session(c).importCode('GSAVE1.nope'),
        throwsA(isA<SaveFormatException>()),
      );
      expect(
        () => session(c).importCode(code.substring(0, code.length - 3)),
        throwsA(isA<SaveFormatException>()),
      );
      expect(c.wallet.of('coins'), before);
    },
  );

  test('a save with no game data is rejected', () {
    store.value = {'saveVersion': 1};
    expect(
      () => session(_newGame()).load(),
      throwsA(isA<SaveFormatException>()),
    );
  });

  test('autosave writes periodically and stops when asked', () async {
    final c = _newGame();
    final s = session(c)..startAutosave(const Duration(milliseconds: 40));
    await Future<void>.delayed(const Duration(milliseconds: 130));
    s.stopAutosave();
    expect(store.value, isNotNull);
    store.value = null;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(store.value, isNull);
  });

  testWidgets(
    'IdleLifecycleHost saves on pause and reports what was earned on resume',
    (tester) async {
      final c = _newGame();
      c.buy(c.generatorIds.first); // 2 coins/s
      final s = session(c);
      OfflineSummary? heard;
      await tester.pumpWidget(
        MaterialApp(
          home: IdleLifecycleHost(
            session: s,
            onAway: (x) => heard = x,
            child: const Text('game'),
          ),
        ),
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(store.value, isNotNull);

      clock.now = clock.now.add(const Duration(hours: 2));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(heard, isNotNull);
      expect(heard!.gained['coins']!.approxEquals(n('14400')), isTrue);
      c.stop();
    },
  );

  group('cloud sync', () {
    test('an empty cloud receives the local game', () async {
      final c = _newGame();
      c.buy(c.generatorIds.first);
      final cloud = MemoryCloudSaveStore();
      final r = await session(c).syncCloud(cloud);
      expect(r, CloudSyncResult.pushed);
      expect(cloud.value, isNotNull);
      c.stop();
    });

    test('a fresh device takes the cloud game', () async {
      final a = _newGame();
      a.buy(a.generatorIds.first, count: 3);
      final cloud = MemoryCloudSaveStore();
      await session(a).syncCloud(cloud);
      a.stop();

      final fresh = _newGame();
      final storeB = MemorySaveStore();
      final sB = IdleSession(
        controller: fresh,
        store: storeB,
        clock: clock.call,
      );
      expect(await sB.syncCloud(cloud), CloudSyncResult.pulled);
      expect(fresh.world.storeOf<Generator>().denseAt(0).owned, 3);
      expect(storeB.read(), isNotNull, reason: 'also kept locally');
      fresh.stop();
    });

    test('the later save wins, and the player can override', () async {
      final a = _newGame();
      a.buy(a.generatorIds.first, count: 2);
      a.tap();
      final sA = session(a)..save();
      final cloud = MemoryCloudSaveStore();
      await sA.syncCloud(cloud);

      // The cloud moves on (another device played later).
      clock.now = clock.now.add(const Duration(hours: 1));
      final b = _newGame();
      b.buy(b.generatorIds.first, count: 5);
      b.tap();
      final sB = IdleSession(
        controller: b,
        store: MemorySaveStore(),
        clock: clock.call,
      )..save();
      await sB.syncCloud(cloud);
      expect(cloud.pushes, 2);

      // Device A syncs again: the cloud is newer, so it is pulled.
      clock.now = clock.now.add(const Duration(hours: 1));
      expect(await sA.syncCloud(cloud), CloudSyncResult.pulled);
      expect(a.world.storeOf<Generator>().denseAt(0).owned, 5);

      // With a resolver that refuses the cloud copy, the local one is pushed instead.
      clock.now = clock.now.add(const Duration(hours: 1));
      a.world.storeOf<Generator>().denseAt(0).owned = 4;
      sA.save();
      var asked = 0;
      final r = await sA.syncCloud(
        cloud,
        resolve: (l, r) {
          asked++;
          return false;
        },
      );
      expect(asked, 1);
      expect(r, CloudSyncResult.pushed);
      expect(
        cloud.pushes,
        3,
        reason: 'the local game was pushed over the cloud copy',
      );
      a.stop();
      b.stop();
    });
  });

  testWidgets(
    'SaveCodePanel exports a code, and importing it on another device restores the game',
    (tester) async {
      final a = _newGame();
      a.buy(a.generatorIds.first, count: 4);
      final sA = session(a);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SaveCodePanel(session: sA)),
        ),
      );
      await tester.tap(find.byKey(const Key('save-export')));
      await tester.pump();
      final code = tester
          .widget<SelectableText>(find.byKey(const Key('save-code')))
          .data!;
      expect(code, startsWith('GSAVE1.'));

      final b = _newGame();
      final sB = IdleSession(
        controller: b,
        store: MemorySaveStore(),
        clock: clock.call,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SaveCodePanel(session: sB)),
        ),
      );
      await tester.enterText(find.byKey(const Key('save-input')), '$code ');
      await tester.tap(find.byKey(const Key('save-import')));
      await tester.pump();
      expect(find.text('Game loaded.'), findsOneWidget);
      expect(b.world.storeOf<Generator>().denseAt(0).owned, 4);

      await tester.enterText(
        find.byKey(const Key('save-input')),
        'GSAVE1.nonsense.00000000',
      );
      await tester.tap(find.byKey(const Key('save-import')));
      await tester.pump();
      expect(find.textContaining('damaged'), findsOneWidget);
      expect(
        b.world.storeOf<Generator>().denseAt(0).owned,
        4,
        reason: 'a bad code changes nothing',
      );
      a.stop();
      b.stop();
    },
  );
}
