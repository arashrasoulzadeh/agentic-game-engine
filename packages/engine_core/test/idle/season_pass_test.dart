import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_idle.dart';
import 'package:test/test.dart';

BigNumber n(String s) => BigNumber.parse(s);

void main() {
  test('claimSeasonPass grants resources and multipliers in order', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    registerIdleComponents(world);
    final wallet = BigTreasury(amounts: {'coins': n('0'), 'gems': n('0')});
    world.storeOf<BigTreasury>().set(world.spawn(), wallet);
    world.storeOf<IdleModifiers>().set(world.spawn(), IdleModifiers());
    final stats = IdleStats(lifetimeEarned: {'coins': n('1500')});
    world.storeOf<IdleStats>().set(world.spawn(), stats);
    world.storeOf<SeasonPass>().set(
      world.spawn(),
      SeasonPass(
        id: 'spring',
        xpStat: 'lifetime:coins',
        tiers: [
          SeasonPassTier(at: n('100'), grant: {'gems': n('1')}),
          SeasonPassTier(at: n('1000'), multiplier: n('1.05')),
          SeasonPassTier(at: n('10000'), grant: {'gems': n('5')}),
        ],
      ),
    );

    expect(claimSeasonPass(world, wallet), 2);
    expect(wallet.of('gems'), n('1'));
    expect(
      world.storeOf<IdleModifiers>().denseAt(0).stack.sources,
      contains('seasonPass:spring:1'),
    );
    expect(world.storeOf<SeasonPass>().denseAt(0).claimed, 2);

    stats.lifetimeEarned['coins'] = n('20000');
    expect(claimSeasonPass(world, wallet), 1);
    expect(wallet.of('gems'), n('6'));
    expect(claimSeasonPass(world, wallet), 0);
  });

  test('checkAchievements also advances the season pass', () {
    final world = World(width: 10, height: 10);
    registerCoreComponents(world);
    registerIdleComponents(world);
    final wallet = BigTreasury(amounts: {'coins': n('0'), 'gems': n('0')});
    world.storeOf<BigTreasury>().set(world.spawn(), wallet);
    world.storeOf<IdleModifiers>().set(world.spawn(), IdleModifiers());
    world.storeOf<IdleStats>().set(
      world.spawn(),
      IdleStats(lifetimeEarned: {'coins': n('200')}),
    );
    world.storeOf<SeasonPass>().set(
      world.spawn(),
      SeasonPass(
        id: 's',
        xpStat: 'lifetime:coins',
        tiers: [SeasonPassTier(at: n('100'), grant: {'gems': n('2')})],
      ),
    );
    checkAchievements(world, wallet);
    expect(wallet.of('gems'), n('2'));
  });
}
