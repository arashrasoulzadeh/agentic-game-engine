import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' as eng;
import 'package:zarvan_idle/zarvan_idle.dart';
import 'package:flutter_test/flutter_test.dart';

const _strength = HeroUpgrade(
  id: 'strength',
  label: 'Strength',
  stat: 'attack',
  perLevel: 0.25,
  baseCost: 20,
  costGrowth: 2,
  maxLevel: 2,
);
const _vitality = HeroUpgrade(
  id: 'vitality',
  label: 'Vitality',
  stat: 'hp',
  perLevel: 0.5,
  baseCost: 10,
  costGrowth: 1.5,
);
const _all = [_strength, _vitality];

List<String> _texts(World world) {
  final store = world.componentsOf<eng.Text>();
  return [for (var i = 0; i < store.length; i++) store.denseAt(i).text];
}

void main() {
  group('HeroProgress', () {
    test('costs grow per level and round up to whole coins', () {
      final p = HeroProgress(coins: 1000);
      expect(p.costOf(_vitality), 10);
      p.buy(_vitality);
      expect(p.costOf(_vitality), 15);
      p.buy(_vitality);
      expect(p.costOf(_vitality), 23); // 22.5 rounded up
    });

    test(
      'buying spends coins and raises the level; too poor changes nothing',
      () {
        final p = HeroProgress(coins: 25);
        expect(p.buy(_strength), isTrue);
        expect(p.coins, 5);
        expect(p.levelOf(_strength), 1);
        expect(p.buy(_strength), isFalse); // costs 40, has 5
        expect(p.coins, 5);
        expect(p.levelOf(_strength), 1);
      },
    );

    test('a maxed upgrade cannot be bought', () {
      final p = HeroProgress(coins: 10000);
      expect(p.buy(_strength), isTrue);
      expect(p.buy(_strength), isTrue);
      expect(p.isMaxed(_strength), isTrue);
      expect(p.canBuy(_strength), isFalse);
      expect(p.buy(_strength), isFalse);
      expect(p.levelOf(_strength), 2);
    });

    test(
      'multiplier adds perLevel of the base for each level of that stat',
      () {
        final p = HeroProgress(coins: 10000);
        expect(p.multiplier('attack', _all), 1);
        p.buy(_strength);
        p.buy(_strength);
        p.buy(_vitality);
        expect(p.multiplier('attack', _all), 1.5);
        expect(p.multiplier('hp', _all), 1.5);
        expect(p.multiplier('armor', _all), 1);
      },
    );

    test(
      'levels given at construction are kept (a retry keeps its upgrades)',
      () {
        final p = HeroProgress(coins: 7, levels: {'strength': 2});
        expect(p.levelOf(_strength), 2);
        expect(p.coins, 7);
      },
    );
  });

  group('UpgradeBar', () {
    late World world;
    late HeroProgress progress;
    late UpgradeBar bar;

    String? region(int i) {
      final sprites = world.componentsOf<eng.Sprite>();
      return sprites.denseAt(i).region;
    }

    setUp(() {
      world = World(width: 180, height: 320);
      registerCoreComponents(world);
      eng.registerFlutterComponents(world);
      progress = HeroProgress(coins: 12);
      bar = UpgradeBar.spawn(
        world,
        atlasId: 'btn',
        upgrades: _all,
        progress: progress,
      );
    });

    test(
      'styles reflect what is affordable and labels show level and cost',
      () {
        // Strength costs 20 (12 coins: disabled), vitality 10 (affordable).
        expect(region(0), 'disabled');
        expect(region(1), 'primary');
        final texts = _texts(world);
        expect(texts, containsAll(['Coins 12', 'Strength 0', '20', '10']));
      },
    );

    test('sync follows progress: buying flips styles and a max reads MAX', () {
      progress.coins = 500;
      progress.buy(_strength);
      progress.buy(_strength);
      bar.sync(world);
      final store = world.componentsOf<eng.Text>();
      final texts = [
        for (var i = 0; i < store.length; i++) store.denseAt(i).text,
      ];
      expect(texts, containsAll(['Strength 2', 'MAX']));
      expect(region(0), 'secondary');
    });

    test('hit maps taps to upgrade ids and misses to null', () {
      // Two buttons spread over x 18..162: centres 54 and 126, y 296.
      expect(bar.hit(const Offset(54, 296)), 'strength');
      expect(bar.hit(const Offset(126, 296)), 'vitality');
      expect(bar.hit(const Offset(90, 296)), isNull);
      expect(bar.hit(const Offset(54, 200)), isNull);
    });

    test(
      'the retry button appears once, is hit-testable and wins its spot',
      () {
        expect(bar.retryVisible, isFalse);
        expect(bar.hit(const Offset(90, 196)), isNull);
        bar.showRetry(world);
        final sprites = world.componentsOf<eng.Sprite>().length;
        bar.showRetry(world); // idempotent
        expect(world.componentsOf<eng.Sprite>().length, sprites);
        expect(bar.retryVisible, isTrue);
        expect(bar.hit(const Offset(90, 196)), UpgradeBar.retryAction);
      },
    );
  });

  test('ButtonSheet regions match the ui_button_atlas layout', () {
    final r = ButtonSheet.regions();
    expect(r.keys, ['primary', 'secondary', 'disabled']);
    expect(r['primary']!.left, 4);
    expect(r['disabled']!.top, 88);
    expect(r['primary']!.width, 96);
    expect(r['primary']!.height, 44);
  });
}
