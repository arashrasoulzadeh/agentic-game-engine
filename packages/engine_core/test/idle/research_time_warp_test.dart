import 'package:engine_core/engine_core.dart';
import 'package:engine_core/engine_core_idle.dart';
import 'package:test/test.dart';

BigNumber n(String s) => BigNumber.parse(s);

void main() {
  late World world;
  late BigTreasury wallet;
  late EntityId lockedGen;
  late EntityId research;
  late EntityId warp;

  setUp(() {
    world = World(width: 10, height: 10);
    registerCoreComponents(world);
    registerIdleComponents(world);
    wallet = BigTreasury(amounts: {'coins': n('10000'), 'gems': n('2')});
    world.storeOf<BigTreasury>().set(world.spawn(), wallet);
    world.storeOf<IdleModifiers>().set(world.spawn(), IdleModifiers());
    world.storeOf<IdleStats>().set(world.spawn(), IdleStats());
    lockedGen = world.spawn();
    world.storeOf<Generator>().set(
      lockedGen,
      Generator(
        id: 'mine',
        cost: GeometricCost(base: n('10'), growth: 1.1),
        output: {'coins': n('5')},
        requires: ['mining'],
      ),
    );
    research = world.spawn();
    world.storeOf<ResearchNode>().set(
      research,
      ResearchNode(
        id: 'mining',
        name: 'Mining',
        cost: {'coins': n('500')},
        unlocks: ['mining'],
      ),
    );
    warp = world.spawn();
    world.storeOf<TimeWarpOffer>().set(
      warp,
      TimeWarpOffer(
        id: 'hour',
        seconds: 3600,
        cost: {'gems': n('1')},
      ),
    );
    world.addSystem(IdleSystem());
  });

  test('buyResearch unlocks tech so a gated generator can be bought', () {
    expect(buyGenerator(world, wallet, lockedGen).failure, BuyFailure.locked);
    expect(buyResearch(world, wallet, research).ok, isTrue);
    expect(availableTech(world, 'player'), contains('mining'));
    expect(buyGenerator(world, wallet, lockedGen).ok, isTrue);
  });

  test('timeWarp credits current income for the requested duration', () {
    final open = world.spawn();
    world.storeOf<Generator>().set(
      open,
      Generator(
        id: 'farm',
        owned: 1,
        cost: GeometricCost(base: n('10'), growth: 1.1),
        output: {'coins': n('2')},
      ),
    );
    recomputeIncome(world, wallet);
    final before = wallet.of('coins');
    final rate = wallet.rateOf('coins');
    final gained = timeWarp(world, wallet, const Duration(hours: 1));
    expect(gained['coins'], rate * n('3600'));
    expect(wallet.of('coins'), before + gained['coins']!);
  });

  test('buyTimeWarp spends gems then applies the offer', () {
    final open = world.spawn();
    world.storeOf<Generator>().set(
      open,
      Generator(
        id: 'farm',
        owned: 1,
        cost: GeometricCost(base: n('10'), growth: 1.1),
        output: {'coins': n('2')},
      ),
    );
    recomputeIncome(world, wallet);
    final beforeGems = wallet.of('gems');
    final beforeCoins = wallet.of('coins');
    expect(buyTimeWarp(world, wallet, warp).ok, isTrue);
    expect(wallet.of('gems'), beforeGems - n('1'));
    expect(wallet.of('coins'), greaterThan(beforeCoins));
  });

  test('loadIdleDefinition wires research and timeWarps from JSON', () {
    final w = World(width: 10, height: 10);
    registerCoreComponents(w);
    loadIdleDefinition(w, {
      'resources': {'coins': {}, 'gems': {}},
      'generators': [
        {
          'id': 'cursor',
          'cost': {'type': 'geometric', 'base': '10', 'growth': 1.1},
          'output': {'coins': '1'},
          'requires': ['mining'],
        },
      ],
      'research': [
        {
          'id': 'mining',
          'cost': {'coins': '1'},
          'unlocks': ['mining'],
        },
      ],
      'timeWarps': [
        {
          'id': 'hour',
          'seconds': 60,
          'cost': {'gems': '1'},
        },
      ],
    });
    expect(w.storeOf<ResearchNode>().length, 1);
    expect(w.storeOf<TimeWarpOffer>().length, 1);
    expect(validateIdleDefinition({
      'research': [
        {'id': 'x', 'cost': {'nope': '1'}},
      ],
      'resources': {'coins': {}},
    }), contains(contains('research[0].cost.nope')));
  });
}
