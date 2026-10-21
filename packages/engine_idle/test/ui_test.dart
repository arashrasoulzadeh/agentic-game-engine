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
  return IdleController(world: w, wallet: wallet);
}

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
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
