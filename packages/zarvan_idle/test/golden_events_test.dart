import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_idle/zarvan_idle_logic.dart';
import 'package:flutter_test/flutter_test.dart';

BigNumber n(String s) => BigNumber.parse(s);

({World world, BigTreasury wallet}) game({List<GoldenReward>? rewards}) {
  final w = World(width: 10, height: 10);
  registerCoreComponents(w);
  registerIdleComponents(w);
  final wallet = BigTreasury(amounts: {'coins': n('0')});
  w.componentsOf<BigTreasury>().set(w.spawn(), wallet);
  w.componentsOf<IdleModifiers>().set(w.spawn(), IdleModifiers());
  w.componentsOf<IdleStats>().set(w.spawn(), IdleStats());
  w.componentsOf<Generator>().set(
    w.spawn(),
    Generator(
      id: 'g',
      owned: 10,
      cost: GeometricCost(base: n('10'), growth: 1.1),
      output: {'coins': n('1')},
    ),
  );
  recomputeIncome(w, wallet);
  w.componentsOf<GoldenEvents>().set(
    w.spawn(),
    GoldenEvents(
      meanInterval: 100,
      lifetime: 10,
      rewards:
          rewards ??
          [
            GoldenReward(
              kind: 'boost',
              multiplier: BigNumber.from(7),
              seconds: 30,
            ),
            GoldenReward(kind: 'payout', seconds: 60),
          ],
    ),
  );
  return (world: w, wallet: wallet);
}

void main() {
  test(
    'an offer appears within 0.5x-1.5x of the mean, and is missed after its lifetime',
    () {
      final g = game();
      final sys = GoldenEventSystem(DeterministicRandom(1));
      final offers = <double>[];
      g.world.events.on<GoldenOfferedEvent>((e) => offers.add(e.lifetime));
      final store = g.world.componentsOf<GoldenEvents>();

      var t = 0.0;
      while (store.denseAt(0).offered == null && t < 200) {
        sys.update(g.world, 1);
        t++;
      }
      g.world.events.flush();
      expect(offers, [10.0], reason: 'the UI is told how long the offer lasts');
      expect(t, inInclusiveRange(50, 151));
      expect(store.denseAt(0).offered, isNotNull);

      for (var i = 0; i < 10; i++) {
        sys.update(g.world, 1);
      }
      expect(store.denseAt(0).offered, isNull, reason: 'missed');
      expect(store.denseAt(0).countdown, greaterThan(0));
    },
  );

  test('the same seed gives the same offers; a different seed does not', () {
    List<int?> run(int seed) {
      final g = game();
      final sys = GoldenEventSystem(DeterministicRandom(seed));
      final seen = <int?>[];
      for (var i = 0; i < 2000; i++) {
        sys.update(g.world, 1);
        final o = g.world.componentsOf<GoldenEvents>().denseAt(0).offered;
        if (o != null) {
          seen.add(i * 10 + o);
          claimGolden(g.world, g.wallet);
        }
      }
      return seen;
    }

    expect(run(7), run(7));
    expect(run(7), isNot(run(8)));
  });

  test('claiming a boost multiplies income, then the offer is gone', () {
    final g = game(
      rewards: [
        GoldenReward(kind: 'boost', multiplier: BigNumber.from(7), seconds: 30),
      ],
    );
    final store = g.world.componentsOf<GoldenEvents>();
    store.denseAt(0)
      ..offered = 0
      ..offerRemaining = 5;
    final reward = claimGolden(g.world, g.wallet)!;
    expect(reward.kind, 'boost');
    expect(g.wallet.rateOf('coins'), n('70'));
    expect(store.denseAt(0).offered, isNull);
    expect(
      claimGolden(g.world, g.wallet),
      isNull,
      reason: 'nothing left to claim',
    );
  });

  test('claiming a payout adds seconds of income and counts it as earned', () {
    final g = game(rewards: [GoldenReward(kind: 'payout', seconds: 60)]);
    g.world.componentsOf<GoldenEvents>().denseAt(0)
      ..offered = 0
      ..offerRemaining = 5;
    claimGolden(g.world, g.wallet);
    expect(g.wallet.of('coins'), n('600'));
    expect(
      g.world.componentsOf<IdleStats>().denseAt(0).lifetimeEarned['coins'],
      n('600'),
    );
  });

  test('state survives a JSON round trip, so a save mid-wait resumes', () {
    final e = GoldenEvents(
      meanInterval: 50,
      lifetime: 8,
      rewards: [GoldenReward(kind: 'payout', seconds: 5, weight: 2)],
      countdown: 12.5,
      offered: 0,
      offerRemaining: 3,
    );
    final back = GoldenEvents.fromJson(e.toJson());
    expect(back.countdown, 12.5);
    expect(back.offered, 0);
    expect(back.rewards.single.weight, 2);
  });

  test('a game with no rewards or no component does nothing', () {
    final g = game(rewards: []);
    final sys = GoldenEventSystem(DeterministicRandom(1));
    for (var i = 0; i < 500; i++) {
      sys.update(g.world, 1);
    }
    expect(g.world.componentsOf<GoldenEvents>().denseAt(0).offered, isNull);
  });
}
