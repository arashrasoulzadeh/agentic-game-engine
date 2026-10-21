import 'package:engine_core/engine_core.dart';
import 'package:engine_idle/engine_idle.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

void main() {
  late List<AnalyticsEvent> events;
  late IdleController c;
  late MemorySaveStore store;
  late DateTime now;

  setUp(() {
    events = [];
    store = MemorySaveStore();
    now = DateTime.utc(2026);
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
    c = IdleController(
      world: w,
      analytics: IdleAnalytics(
        sink: (e) async {
          events.add(e);
        },
      ),
    );
  });

  test('a purchase reports what was bought and what it cost', () {
    c.buy(c.generatorIds.first, count: 3);
    final e = events.single;
    expect(e.name, IdleAnalytics.purchaseEvent);
    expect(e.payload['id'], 'cursor');
    expect(e.payload['count'], 3);
    expect((e.payload['spent'] as Map)['coins'], greaterThan(0));
  });

  test('a refused purchase reports nothing', () {
    c.wallet.amounts['coins'] = BigNumber.zero;
    c.buy(c.generatorIds.first);
    expect(events, isEmpty);
  });

  test('upgrades and prestige are reported', () {
    c.buy(c.generatorIds.first);
    c.buyUpgradeById(c.upgradeIds.first);
    c.world.storeOf<IdleStats>().denseAt(0).credit({'coins': n('10000')});
    c.prestige();
    expect(events.map((e) => e.name), [
      IdleAnalytics.purchaseEvent,
      IdleAnalytics.purchaseEvent,
      IdleAnalytics.prestigeEvent,
    ]);
    expect(events[1].payload['id'], 'x2');
    expect(events.last.payload['gain'], 10);
    expect(events.last.payload['count'], 1);
  });

  test('coming back after a while reports the away time and earnings', () {
    c.buy(c.generatorIds.first);
    events.clear();
    final s = IdleSession(controller: c, store: store, clock: () => now)
      ..onPause();
    now = now.add(const Duration(hours: 2));
    s.onResume();
    final e = events.single;
    expect(e.name, IdleAnalytics.offlineReturnEvent);
    expect(e.payload['awaySeconds'], 7200);
    expect(e.payload['capped'], false);
    expect((e.payload['gained'] as Map)['coins'], 7200);
    c.stop();
  });

  test('without analytics nothing breaks', () {
    final bare = IdleController(world: c.world);
    expect(bare.buy(bare.generatorIds.first).ok, isTrue);
  });
}
