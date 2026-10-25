import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

IdleController _controller({String coins = '1000', int generators = 2}) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerIdleComponents(w);
  final wallet = BigTreasury(amounts: {'coins': n(coins)});
  w.storeOf<BigTreasury>().set(w.spawn(), wallet);
  w.storeOf<IdleModifiers>().set(w.spawn(), IdleModifiers());
  w.storeOf<IdleStats>().set(w.spawn(), IdleStats());
  for (var i = 0; i < generators; i++) {
    w.storeOf<Generator>().set(
      w.spawn(),
      Generator(
        id: 'gen$i',
        name: 'Generator $i',
        cost: GeometricCost(base: n('10'), growth: 1.15),
        output: {'coins': n('1')},
      ),
    );
  }
  w.addSystem(IdleSystem());
  return IdleController(world: w);
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets(
    'the settings panel switches the number style everywhere and states the offline rules',
    (tester) async {
      final c = _controller(coins: '1234567');
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              ResourceHeader(controller: c),
              IdleSettingsPanel(
                controller: c,
                offline: const OfflineConfig(
                  cap: Duration(hours: 6),
                  efficiency: 0.5,
                ),
              ),
            ],
          ),
        ),
      );
      expect(find.text('1.23M'), findsOneWidget);
      expect(
        find.textContaining('50% of your income, for up to 6 hours'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('settings-decimal-separator')), findsOneWidget);
      NumberStyle? persisted;
      String? sepPersisted;
      await tester.pumpWidget(
        _app(
          Column(
            children: [
              ResourceHeader(controller: c),
              IdleSettingsPanel(
                controller: c,
                offline: const OfflineConfig(
                  cap: Duration(hours: 6),
                  efficiency: 0.5,
                ),
                onStyleChanged: (s) => persisted = s,
                onDecimalSeparatorChanged: (s) => sepPersisted = s,
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('1.5e6'));
      await tester.pump();
      expect(c.style, NumberStyle.scientific);
      expect(persisted, NumberStyle.scientific);
      expect(find.text('1.23e6'), findsOneWidget);
      await tester.tap(find.text('1,5'));
      await tester.pump();
      expect(c.decimalSeparator, ',');
      expect(sepPersisted, ',');
      expect(c.resourceIds, ['coins']);
    },
  );

  testWidgets('the controller writes numbers with the locale decimal mark', (
    tester,
  ) async {
    final c = _controller(coins: '1234567');
    c.decimalSeparator = ',';
    await tester.pumpWidget(_app(ResourceHeader(controller: c)));
    expect(find.text('1,23M'), findsOneWidget);
  });

  test(
    'format remembers results, and a style or separator change misses the cache',
    () {
      final c = _controller();
      expect(c.format(n('1234567')), '1.23M');
      expect(c.format(n('1234567')), '1.23M');
      expect(c.formatCacheSize, 1);
      c.style = NumberStyle.scientific;
      expect(c.format(n('1234567')), '1.23e6');
      c.decimalSeparator = ',';
      expect(c.format(n('1234567')), '1,23e6');
      expect(c.formatCacheSize, 3);
    },
  );

  test('the format cache stays bounded', () {
    final c = _controller();
    for (var i = 0; i < 3000; i++) {
      c.format(BigNumber.from(i + 1.5));
    }
    expect(c.formatCacheSize, lessThanOrEqualTo(1024));
  });

  group('challenge panel', () {
    testWidgets(
      'lists a challenge, starts it after confirming, and shows it running with an Abandon button',
      (tester) async {
        final c = _controller();
        c.world.storeOf<Challenge>().set(
          c.world.spawn(),
          Challenge(
            id: 'frugal',
            name: 'Frugal',
            rules: ['noUpgrades'],
            goalStat: 'run:coins',
            goalAtLeast: n('500'),
            reward: n('3'),
          ),
        );
        await tester.pumpWidget(_app(ChallengePanel(controller: c)));
        expect(find.text('Frugal'), findsOneWidget);
        expect(find.textContaining('No upgrades'), findsOneWidget);
        expect(find.textContaining('reward x3'), findsOneWidget);

        await tester.tap(find.byKey(const Key('challenge-start-frugal')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('challenge-confirm-frugal')));
        await tester.pumpAndSettle();
        expect(activeChallenge(c.world)!.id, 'frugal');
        expect(
          find.byKey(const Key('challenge-abandon-frugal')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('challenge-abandon-frugal')));
        await tester.pumpAndSettle();
        expect(activeChallenge(c.world), isNull);
        expect(find.byKey(const Key('challenge-start-frugal')), findsOneWidget);
      },
    );

    testWidgets('StatsPanel shows taps, prestiges and play time', (
      tester,
    ) async {
      final c = _controller();
      final stats = c.world.storeOf<IdleStats>().denseAt(0);
      stats.taps = 7;
      stats.prestigeCount = 2;
      stats.secondsPlayed = 3660;
      await tester.pumpWidget(_app(StatsPanel(controller: c)));
      expect(find.byKey(const Key('stats-panel')), findsOneWidget);
      expect(find.byKey(const Key('stats-taps')), findsOneWidget);
      expect(find.textContaining('7'), findsWidgets);
      expect(find.textContaining('2'), findsWidgets);
    });

    testWidgets(
      'a game without challenges shows nothing; a completed one has no button',
      (tester) async {
        final c = _controller();
        await tester.pumpWidget(_app(ChallengePanel(controller: c)));
        expect(find.byType(ListTile), findsNothing);

        c.world.storeOf<Challenge>().set(
          c.world.spawn(),
          Challenge(
            id: 'done',
            goalStat: 'taps',
            goalAtLeast: n('1'),
            completed: true,
          ),
        );
        c.refresh();
        await tester.pump();
        expect(find.textContaining('Completed'), findsOneWidget);
        expect(find.byKey(const Key('challenge-start-done')), findsNothing);
      },
    );
  });

  group('golden offer', () {
    IdleController withGolden() {
      final c = _controller(coins: '0');
      c.world.storeOf<GoldenEvents>().set(
        c.world.spawn(),
        GoldenEvents(
          meanInterval: 60,
          lifetime: 10,
          rewards: [GoldenReward(kind: 'payout', seconds: 60)],
        ),
      );
      c.wallet.incomePerSecond['coins'] = n('10');
      return c;
    }

    testWidgets(
      'shows nothing until an offer appears, then pays out when pressed',
      (tester) async {
        final c = withGolden();
        GoldenReward? claimed;
        await tester.pumpWidget(
          _app(GoldenOffer(controller: c, onClaimed: (r) => claimed = r)),
        );
        expect(find.byKey(const Key('golden-offer')), findsNothing);

        final g = c.world.storeOf<GoldenEvents>().denseAt(0)
          ..offered = 0
          ..offerRemaining = 7.2;
        c.refresh();
        await tester.pump();
        expect(find.text('Bonus · 8s'), findsOneWidget);

        await tester.tap(find.byKey(const Key('golden-offer')));
        await tester.pump();
        expect(c.wallet.of('coins'), n('600'));
        expect(claimed!.kind, 'payout');
        expect(g.offered, isNull);
        expect(find.byKey(const Key('golden-offer')), findsNothing);
      },
    );

    testWidgets(
      'a game without golden events shows nothing and claiming does nothing',
      (tester) async {
        final c = _controller();
        await tester.pumpWidget(_app(GoldenOffer(controller: c)));
        expect(find.byKey(const Key('golden-offer')), findsNothing);
        expect(c.claimGoldenOffer(), isNull);
      },
    );

    testWidgets('describe names the reward', (tester) async {
      final c = withGolden();
      c.world.storeOf<GoldenEvents>().denseAt(0)
        ..offered = 0
        ..offerRemaining = 3;
      await tester.pumpWidget(
        _app(
          GoldenOffer(controller: c, describe: (r) => 'One minute of income'),
        ),
      );
      expect(find.text('One minute of income · 3s'), findsOneWidget);
    });
  });

  group('prestige panel and achievements', () {
    IdleController game() {
      final c = _controller(coins: '0');
      c.world.storeOf<PrestigeRule>().set(
        c.world.spawn(),
        PrestigeRule(currency: 'gems', basedOn: 'coins', divisor: n('100')),
      );
      c.world.storeOf<Achievement>().set(
        c.world.spawn(),
        Achievement(
          id: 'rich',
          name: 'Rich',
          stat: 'lifetime:coins',
          atLeast: n('1000'),
        ),
      );
      return c;
    }

    testWidgets(
      'prestige is disabled until it would pay, then asks before resetting',
      (tester) async {
        final c = game();
        await tester.pumpWidget(_app(PrestigePanel(controller: c)));
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('prestige-button')))
              .onPressed,
          isNull,
        );
        expect(find.textContaining('Earn more coins'), findsOneWidget);

        c.world.storeOf<IdleStats>().denseAt(0).credit({'coins': n('10000')});
        c.wallet.add('coins', n('10000'));
        c.refresh();
        await tester.pump();
        expect(find.textContaining('+10 gems'), findsOneWidget);

        await tester.tap(find.byKey(const Key('prestige-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('prestige-cancel')));
        await tester.pumpAndSettle();
        expect(c.wallet.of('gems'), BigNumber.zero, reason: 'cancelled');

        await tester.tap(find.byKey(const Key('prestige-button')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('prestige-confirm-yes')));
        await tester.pumpAndSettle();
        expect(c.wallet.of('gems'), n('10'));
        expect(c.wallet.of('coins'), BigNumber.zero);
      },
    );

    testWidgets('achievements show progress, then done once unlocked', (
      tester,
    ) async {
      final c = game();
      c.world.storeOf<IdleStats>().denseAt(0).credit({'coins': n('250')});
      await tester.pumpWidget(_app(AchievementList(controller: c)));
      expect(find.text('Rich'), findsOneWidget);
      expect(find.text('250 / 1.00K'), findsOneWidget);

      c.world.storeOf<IdleStats>().denseAt(0).credit({'coins': n('5000')});
      c.tap();
      await tester.pump();
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets(
      'a second layer gets its own panel with its own keys and prestiges that layer',
      (tester) async {
        final c = game();
        c.world.storeOf<PrestigeRule>().set(
          c.world.spawn(),
          PrestigeRule(
            id: 'ascend',
            currency: 'stars',
            basedOn: 'gems',
            divisor: n('1'),
          ),
        );
        c.wallet.add('gems', n('9'));
        c.world.storeOf<IdleStats>().denseAt(0).credit({'gems': n('9')});
        c.refresh();
        await tester.pumpWidget(
          _app(
            Column(
              children: [
                PrestigePanel(controller: c),
                PrestigePanel(controller: c, ruleId: 'ascend'),
              ],
            ),
          ),
        );
        expect(find.byKey(const Key('prestige-button')), findsOneWidget);
        expect(find.byKey(const Key('prestige-button-ascend')), findsOneWidget);
        expect(
          find.textContaining('+3 stars'),
          findsOneWidget,
          reason: 'sqrt(9 / 1)',
        );

        await tester.tap(find.byKey(const Key('prestige-button-ascend')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('prestige-confirm-yes-ascend')));
        await tester.pumpAndSettle();
        expect(c.wallet.of('stars'), n('3'));
      },
    );

    testWidgets('a game without prestige shows nothing', (tester) async {
      await tester.pumpWidget(_app(PrestigePanel(controller: _controller())));
      expect(find.byKey(const Key('prestige-button')), findsNothing);
    });
  });

  testWidgets(
    'ResourceHeader shows the formatted amount and rate, and follows ticks',
    (tester) async {
      final c = _controller(coins: '1234');
      c.wallet.incomePerSecond['coins'] = n('5');
      await tester.pumpWidget(_app(ResourceHeader(controller: c)));
      expect(find.byKey(const Key('amount-coins')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('amount-coins'))).data,
        '1.23K',
      );
      expect(find.textContaining('5/s'), findsOneWidget);

      c.tick(1000);
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('amount-coins'))).data,
        '6.23K',
      );
    },
  );

  testWidgets(
    'ThrottledListenableBuilder coalesces rapid ticks but actions rebuild immediately',
    (tester) async {
      final c = _controller(coins: '100');
      var builds = 0;
      await tester.pumpWidget(
        _app(
          ThrottledListenableBuilder(
            listenable: c,
            interval: const Duration(milliseconds: 200),
            urgentOf: () => c.urgentGeneration,
            builder: (context, _) {
              builds++;
              return Text(
                '${c.world.storeOf<Generator>().get(c.generatorIds.first)!.owned}',
                key: const Key('owned'),
              );
            },
          ),
        ),
      );
      expect(builds, 1);
      for (var i = 0; i < 5; i++) {
        c.tick(0.1);
      }
      await tester.pump();
      expect(
        builds,
        2,
        reason: 'first tick rebuilds immediately; the rest wait',
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(builds, 3, reason: 'trailing flush after the interval');
      final buildsBeforeBuy = builds;
      c.buy(c.generatorIds.first);
      await tester.pump();
      expect(
        builds,
        buildsBeforeBuy + 1,
        reason: 'urgentGeneration bypasses the throttle',
      );
      expect(tester.widget<Text>(find.byKey(const Key('owned'))).data, '1');
    },
  );

  testWidgets('the number style switches everywhere at once', (tester) async {
    final c = _controller(coins: '1234567');
    await tester.pumpWidget(_app(ResourceHeader(controller: c)));
    expect(
      tester.widget<Text>(find.byKey(const Key('amount-coins'))).data,
      '1.23M',
    );
    c.style = NumberStyle.scientific;
    c.tick(0);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('amount-coins'))).data,
      '1.23e6',
    );
  });

  group('GeneratorList', () {
    testWidgets(
      'shows progress to the next milestone, and nothing once all are reached',
      (tester) async {
        final c = _controller(generators: 1);
        final g = c.world.storeOf<Generator>().get(c.generatorIds.first)!;
        g.milestones.addAll([Milestone(10, n('2')), Milestone(25, n('3'))]);
        g.owned = 4;
        await tester.pumpWidget(_app(GeneratorList(controller: c)));
        expect(
          find.textContaining('Next bonus: ×2 at 10 (6 to go)'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byKey(const Key('milestone-bar-gen0')),
              )
              .value,
          closeTo(0.4, 1e-9),
        );
        g.owned = 10;
        c.refresh();
        await tester.pump();
        expect(
          find.textContaining('Next bonus: ×3 at 25 (15 to go)'),
          findsOneWidget,
        );
        g.owned = 25;
        c.refresh();
        await tester.pump();
        expect(find.byKey(const Key('milestone-gen0')), findsNothing);
        expect(g.nextMilestone, isNull);
      },
    );

    testWidgets('lists each generator with its owned count', (tester) async {
      final c = _controller();
      await tester.pumpWidget(_app(GeneratorList(controller: c)));
      expect(find.byKey(const Key('name-gen0')), findsOneWidget);
      expect(find.byKey(const Key('name-gen1')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('owned-gen0'))).data,
        '0',
      );
    });

    testWidgets(
      'buying ×1 spends the price and the row, header and rate update',
      (tester) async {
        final c = _controller(coins: '100');
        await tester.pumpWidget(
          _app(
            Column(
              children: [
                ResourceHeader(controller: c),
                Expanded(child: GeneratorList(controller: c)),
              ],
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('buy-gen0-×1')));
        await tester.pump();
        expect(
          tester.widget<Text>(find.byKey(const Key('owned-gen0'))).data,
          '1',
        );
        expect(
          tester.widget<Text>(find.byKey(const Key('amount-coins'))).data,
          '90',
        );
        expect(find.textContaining('1/s'), findsWidgets);
      },
    );

    testWidgets('buttons are disabled when that many cannot be afforded', (
      tester,
    ) async {
      final c = _controller(coins: '25');
      await tester.pumpWidget(_app(GeneratorList(controller: c)));
      bool enabled(String label) =>
          tester
              .widget<FilledButton>(find.byKey(Key('buy-gen0-$label')))
              .onPressed !=
          null;
      expect(enabled('×1'), isTrue);
      expect(enabled('×10'), isFalse);
      expect(enabled('×100'), isFalse);
      expect(enabled('Max'), isTrue);
    });

    testWidgets('Max buys everything affordable', (tester) async {
      final c = _controller(coins: '100');
      await tester.pumpWidget(_app(GeneratorList(controller: c)));
      final expected = GeometricCost(
        base: n('10'),
        growth: 1.15,
      ).maxAffordable(0, n('100'));
      await tester.tap(find.byKey(const Key('buy-gen0-Max')));
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const Key('owned-gen0'))).data,
        '$expected',
      );
    });

    testWidgets('a locked generator says what it needs and cannot be bought', (
      tester,
    ) async {
      final c = _controller();
      c.world.storeOf<Generator>().set(
        c.world.spawn(),
        Generator(
          id: 'lab',
          cost: GeometricCost(base: n('1'), growth: 1.1),
          requires: ['science'],
        ),
      );
      await tester.pumpWidget(_app(GeneratorList(controller: c)));
      await tester.scrollUntilVisible(find.byKey(const Key('locked-lab')), 200);
      expect(find.byKey(const Key('locked-lab')), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('buy-lab-×1')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('a long list is virtualised: only visible rows are built', (
      tester,
    ) async {
      final c = _controller(generators: 300);
      await tester.pumpWidget(_app(GeneratorList(controller: c)));
      expect(find.byType(GeneratorRow).evaluate().length, lessThan(30));
      await tester.scrollUntilVisible(
        find.byKey(const Key('name-gen250')),
        400,
        scrollable: find.byType(Scrollable),
        maxScrolls: 200,
      );
      expect(find.byKey(const Key('name-gen250')), findsOneWidget);
    });

    testWidgets('exposes a semantic label per row', (tester) async {
      final handle = tester.ensureSemantics();
      final c = _controller();
      await tester.pumpWidget(_app(GeneratorList(controller: c)));
      expect(
        find.bySemanticsLabel(RegExp('Generator 0, 0 owned')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('UpgradeList', () {
    testWidgets('shows cost and effect, buys once, then shows Bought', (
      tester,
    ) async {
      final c = _controller(coins: '500');
      c.world.storeOf<Upgrade>().set(
        c.world.spawn(),
        Upgrade(
          id: 'x2',
          name: 'Double',
          target: 'gen0',
          multiplier: n('2'),
          cost: {'coins': n('200')},
        ),
      );
      await tester.pumpWidget(_app(UpgradeList(controller: c)));
      expect(find.textContaining('200'), findsOneWidget);
      await tester.tap(find.byKey(const Key('buy-upgrade-x2')));
      await tester.pump();
      expect(find.text('Bought'), findsOneWidget);
      expect(c.wallet.of('coins'), n('300'));
    });

    testWidgets('too expensive means a disabled button', (tester) async {
      final c = _controller(coins: '5');
      c.world.storeOf<Upgrade>().set(
        c.world.spawn(),
        Upgrade(id: 'x2', multiplier: n('2'), cost: {'coins': n('200')}),
      );
      await tester.pumpWidget(_app(UpgradeList(controller: c)));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('buy-upgrade-x2')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('costResource filters to that currency (prestige shop)', (
      tester,
    ) async {
      final c = _controller(coins: '500');
      c.wallet.amounts['gems'] = n('10');
      c.world.storeOf<Upgrade>().set(
        c.world.spawn(),
        Upgrade(id: 'coin_up', multiplier: n('2'), cost: {'coins': n('10')}),
      );
      c.world.storeOf<Upgrade>().set(
        c.world.spawn(),
        Upgrade(id: 'gem_up', multiplier: n('2'), cost: {'gems': n('5')}),
      );
      await tester.pumpWidget(
        _app(SizedBox(height: 400, child: PrestigeShop(controller: c))),
      );
      expect(find.byKey(const Key('prestige-shop-gems')), findsOneWidget);
      expect(find.byKey(const Key('upgrade-gem_up')), findsOneWidget);
      expect(find.byKey(const Key('upgrade-coin_up')), findsNothing);
    });
  });

  test('IdleSfx fires on successful buy, tap, upgrade and prestige', () {
    final heard = <String>[];
    final w = World(width: 10, height: 10);
    registerCoreComponents(w);
    registerIdleComponents(w);
    w.storeOf<BigTreasury>().set(
      w.spawn(),
      BigTreasury(amounts: {'coins': n('100000')}),
    );
    w.storeOf<IdleModifiers>().set(w.spawn(), IdleModifiers());
    w.storeOf<IdleStats>().set(w.spawn(), IdleStats());
    w.storeOf<Generator>().set(
      w.spawn(),
      Generator(
        id: 'cursor',
        cost: GeometricCost(base: n('10'), growth: 1.1),
        output: {'coins': n('1')},
      ),
    );
    w.storeOf<Upgrade>().set(
      w.spawn(),
      Upgrade(
        id: 'x2',
        target: 'cursor',
        multiplier: n('2'),
        cost: {'coins': n('50')},
      ),
    );
    w.storeOf<PrestigeRule>().set(
      w.spawn(),
      PrestigeRule(currency: 'gems', basedOn: 'coins', divisor: n('100')),
    );
    w.addSystem(IdleSystem());
    final c = IdleController(
      world: w,
      sfx: IdleSfx(
        onBuy: () => heard.add('buy'),
        onUpgrade: () => heard.add('upgrade'),
        onTap: () => heard.add('tap'),
        onPrestige: () => heard.add('prestige'),
      ),
    );
    c.buy(c.generatorIds.first);
    c.tap();
    c.buyUpgradeById(c.upgradeIds.first);
    w.storeOf<IdleStats>().denseAt(0).credit({'coins': n('10000')});
    c.prestige();
    expect(heard, ['buy', 'tap', 'upgrade', 'prestige']);
    c.dispose();
  });

  testWidgets('pause menu offers resume, settings and credits', (tester) async {
    var settings = 0;
    var credits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              key: const Key('open-pause'),
              onPressed: () => showIdlePauseMenu(
                context,
                onSettings: () => settings++,
                onCredits: () => credits++,
              ),
              child: const Text('Pause'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-pause')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pause-resume')), findsOneWidget);
    await tester.tap(find.byKey(const Key('pause-settings')));
    await tester.pumpAndSettle();
    expect(settings, 1);

    await tester.tap(find.byKey(const Key('open-pause')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pause-credits')));
    await tester.pumpAndSettle();
    expect(credits, 1);
  });

  testWidgets('settings panel volume sliders write PlayerOptions', (tester) async {
    final c = _controller();
    final options = PlayerOptionsManager(InMemoryPlayerOptionsStorage());
    await tester.pumpWidget(
      _app(IdleSettingsPanel(controller: c, options: options)),
    );
    expect(find.byKey(const Key('settings-master-volume')), findsOneWidget);
    await tester.drag(find.byKey(const Key('settings-master-volume')), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(options.options.masterVolume, lessThan(1.0));
  });

  testWidgets('OfflineSummaryDialog lists time away, the cap and each gain', (
    tester,
  ) async {
    final c = _controller();
    c.wallet.incomePerSecond['coins'] = n('10');
    final t0 = DateTime.utc(2026);
    final summary = OfflineProgress.catchUp(
      c.wallet,
      lastActiveAt: t0,
      now: t0.add(const Duration(hours: 20)),
    );
    await tester.pumpWidget(
      _app(OfflineSummaryDialog(summary: summary, format: c.format)),
    );
    expect(find.textContaining('20h 0m'), findsOneWidget);
    expect(find.textContaining('capped at 8h 0m'), findsOneWidget);
    expect(find.byKey(const Key('offline-gain-coins')), findsOneWidget);
    expect(find.textContaining('288.00K'), findsOneWidget);
  });

  testWidgets(
    'the double button appears only when offered and pops true once the reward is earned',
    (tester) async {
      final c = _controller();
      c.wallet.incomePerSecond['coins'] = n('10');
      final t0 = DateTime.utc(2026);
      final summary = OfflineProgress.catchUp(
        c.wallet,
        lastActiveAt: t0,
        now: t0.add(const Duration(hours: 1)),
      );
      await tester.pumpWidget(
        _app(OfflineSummaryDialog(summary: summary, format: c.format)),
      );
      expect(find.byKey(const Key('offline-double')), findsNothing);

      Object? result = 'unset';
      var granted = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => TextButton(
              key: const Key('open'),
              onPressed: () async {
                result = await showDialog<bool>(
                  context: context,
                  builder: (_) => OfflineSummaryDialog(
                    summary: summary,
                    format: c.format,
                    onDouble: () async => granted,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('offline-double')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('offline-summary')),
        findsOneWidget,
        reason: 'ad not completed: stays open',
      );
      granted = true;
      await tester.tap(find.byKey(const Key('offline-double')));
      await tester.pumpAndSettle();
      expect(result, true);
    },
  );

  test(
    'the controller steps the world on a real timer, and stops when asked',
    () async {
      final c = _controller(coins: '0');
      c.wallet.incomePerSecond['coins'] = n('1000');
      var notifications = 0;
      c.addListener(() => notifications++);
      c.start();
      await Future<void>.delayed(const Duration(milliseconds: 450));
      c.stop();
      final after = c.wallet.of('coins');
      expect(after > BigNumber.zero, isTrue);
      expect(notifications, greaterThanOrEqualTo(2));
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(c.wallet.of('coins'), after, reason: 'stopped');
      c.dispose();
    },
  );

  testWidgets('prestige through the controller notifies listeners', (
    tester,
  ) async {
    final c = _controller(coins: '5');
    c.world.storeOf<PrestigeRule>().set(
      c.world.spawn(),
      PrestigeRule(currency: 'gems', basedOn: 'coins', divisor: n('100')),
    );
    c.world.storeOf<IdleStats>().denseAt(0).credit({'coins': n('10000')});
    var heard = 0;
    c.addListener(() => heard++);
    expect(c.prestige(), n('10'));
    expect(heard, 1);
    expect(c.prestige(), isNull, reason: 'nothing earned since');
    expect(heard, 1);
  });
}
