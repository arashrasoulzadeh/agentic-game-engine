import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/src/register_components.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart'
    as eng
    show BackdropBlur, Sprite, Text;
import 'package:zarvan_idle/zarvan_idle.dart';

World _world() {
  final w = World(width: 180, height: 320);
  registerCoreComponents(w);
  registerFlutterComponents(w);
  return w;
}

int _spritesIn(World w, String atlas) {
  final sprites = w.componentsOf<eng.Sprite>();
  var n = 0;
  for (var i = 0; i < sprites.length; i++) {
    if (sprites.denseAt(i).atlasId == atlas) n++;
  }
  return n;
}

void main() {
  const upgrades = [
    HeroUpgrade(id: 'strength', label: 'Strength', stat: 'attack', icon: 0),
    HeroUpgrade(id: 'vitality', label: 'Vitality', stat: 'hp', icon: 1),
    HeroUpgrade(id: 'guard', label: 'Guard', stat: 'armor'),
  ];

  test('buttons with an icon index draw one icon sprite each', () {
    final w = _world();
    UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      iconAtlasId: 'icons',
      upgrades: upgrades,
      progress: HeroProgress(),
    );
    expect(_spritesIn(w, 'btn'), 3);
    expect(_spritesIn(w, 'icons'), 2, reason: 'guard has no icon');
  });

  test('icons are drawn at the picked frame and on the left of the label', () {
    final w = _world();
    UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      iconAtlasId: 'icons',
      upgrades: upgrades,
      progress: HeroProgress(),
    );
    final sprites = w.componentsOf<eng.Sprite>();
    final positions = w.componentsOf<Position>();
    final regions = <String>[];
    for (var i = 0; i < sprites.length; i++) {
      final s = sprites.denseAt(i);
      if (s.atlasId != 'icons') continue;
      regions.add(s.region);
      final x = positions.get(sprites.entityAt(i))!.x;
      // strength is the first of three buttons: its centre is left of 90.
      if (s.region == '0') expect(x, lessThan(60));
    }
    expect(regions..sort(), ['0', '1']);
  });

  test('icon-only buttons centre the icon and show no words', () {
    final w = _world();
    final bar = UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      iconAtlasId: 'icons',
      upgrades: upgrades,
      layout: const UpgradeLayout(iconOnly: true),
      progress: HeroProgress(coins: 1000),
    );
    bar.sync(w);
    final store = w.componentsOf<eng.Text>();
    final texts = [
      for (var i = 0; i < store.length; i++) store.denseAt(i).text,
    ].where((t) => t.isNotEmpty);
    // No labels ("Strength 0"), only costs; the unicon "guard" keeps its words.
    expect(texts.where((t) => t.contains('Strength')), isEmpty);
    expect(texts.where((t) => t.contains('Vitality')), isEmpty);
    expect(texts.where((t) => t.contains('Guard')), isNotEmpty);
  });

  test('a menu hides the upgrades until its button is tapped', () {
    final w = _world();
    final bar = UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      upgrades: upgrades,
      layout: const UpgradeLayout(menu: true, y: 250, menuX: 90, menuY: 308),
      progress: HeroProgress(coins: 1000),
    );
    expect(bar.menuOpen, isFalse);
    expect(bar.hit(const Offset(30, 250)), isNull, reason: 'panel is closed');
    expect(bar.hit(const Offset(90, 308)), UpgradeBar.menuAction);
    bar.toggleMenu(w);
    expect(bar.menuOpen, isTrue);
    expect(bar.hit(const Offset(30, 250)), 'strength');
    final sprites = w.componentsOf<eng.Sprite>();
    final positions = w.componentsOf<Position>();
    for (var i = 0; i < sprites.length; i++) {
      expect(positions.get(sprites.entityAt(i))!.y, lessThan(400));
    }
    bar.toggleMenu(w);
    expect(bar.hit(const Offset(30, 250)), isNull);
  });

  test('the dialog holds skills too, with a nine-piece frame, and pauses', () {
    final w = _world();
    final bar = UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      frameAtlasId: 'frame',
      upgrades: upgrades,
      skills: const [
        HeroSkill(id: 'strike', label: 'Strike', kind: SkillKind.strike),
      ],
      layout: const UpgradeLayout(menu: true, y: 190, skillY: 140),
      progress: HeroProgress(),
    );
    expect(_spritesIn(w, 'frame'), 10, reason: 'nine pieces and the veil');
    expect(bar.dialogOpen, isFalse);
    expect(bar.hit(const Offset(90, 140)), isNull, reason: 'closed');
    bar.toggleMenu(w);
    expect(bar.dialogOpen, isTrue);
    expect(bar.hit(const Offset(90, 140)), '${UpgradeBar.skillPrefix}strike');
    final sprites = w.componentsOf<eng.Sprite>();
    final positions = w.componentsOf<Position>();
    for (var i = 0; i < sprites.length; i++) {
      final y = positions.get(sprites.entityAt(i))!.y;
      if (sprites.denseAt(i).atlasId == 'frame') {
        expect(y, inInclusiveRange(70, 250));
      }
    }
  });

  test('the dialog fades in and out and leaves the screen when closed', () {
    final w = _world();
    final bar = UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      frameAtlasId: 'frame',
      upgrades: upgrades,
      layout: const UpgradeLayout(menu: true, y: 190),
      progress: HeroProgress(),
    );
    int? tintOfFrame() {
      final sprites = w.componentsOf<eng.Sprite>();
      for (var i = 0; i < sprites.length; i++) {
        final s = sprites.denseAt(i);
        if (s.atlasId == 'frame' && s.region == 'f00') return s.tintArgb;
      }
      return null;
    }

    double maxY() {
      final p = w.componentsOf<Position>();
      var m = 0.0;
      for (var i = 0; i < p.length; i++) {
        if (p.denseAt(i).y > m) m = p.denseAt(i).y;
      }
      return m;
    }

    bar.toggleMenu(w);
    bar.update(w, 0.1);
    final half = (tintOfFrame()! >> 24) & 0xFF;
    expect(half, inInclusiveRange(100, 150), reason: 'half way in');
    bar.update(w, 0.2);
    expect((tintOfFrame()! >> 24) & 0xFF, 255);
    bar.toggleMenu(w);
    bar.update(w, 0.1);
    expect(maxY(), lessThan(400), reason: 'still fading out, still visible');
    bar.update(w, 0.2);
    expect(maxY(), greaterThan(1000), reason: 'gone once faded');
  });

  test(
    'the dialog lists upgrades one per row, with descriptions and a blur',
    () {
      final w = _world();
      const described = [
        HeroUpgrade(
          id: 'strength',
          label: 'Strength',
          stat: 'attack',
          description: 'More damage per hit',
        ),
        HeroUpgrade(id: 'vitality', label: 'Vitality', stat: 'hp'),
      ];
      final bar = UpgradeBar.spawn(
        w,
        atlasId: 'btn',
        frameAtlasId: 'frame',
        upgrades: described,
        layout: const UpgradeLayout(menu: true, y: 150, rowHeight: 30),
        progress: HeroProgress(coins: 1000),
      );
      bar.toggleMenu(w);
      expect(bar.hit(const Offset(60, 150)), 'strength');
      expect(bar.hit(const Offset(60, 180)), 'vitality');
      expect(bar.hit(const Offset(60, 120)), isNull, reason: 'above the rows');
      final texts = w.componentsOf<eng.Text>();
      final all = [
        for (var i = 0; i < texts.length; i++) texts.denseAt(i).text,
      ];
      expect(all, contains('More damage per hit'));
      expect(all, contains('Strength  0'));

      final blur = w.componentsOf<eng.BackdropBlur>();
      expect(blur.length, 1);
      expect(blur.denseAt(0).sigma, 0, reason: 'not faded in yet');
      bar.update(w, 0.3);
      expect(blur.denseAt(0).sigma, 3);
      bar.toggleMenu(w);
      bar.update(w, 0.3);
      expect(blur.denseAt(0).sigma, 0);
    },
  );

  test('without an icon atlas nothing changes', () {
    final w = _world();
    UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      upgrades: upgrades,
      progress: HeroProgress(),
    );
    expect(_spritesIn(w, 'btn'), 3);
    expect(_spritesIn(w, 'icons'), 0);
  });

  test('hit-testing is unchanged by icons', () {
    final w = _world();
    final bar = UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      iconAtlasId: 'icons',
      upgrades: upgrades,
      progress: HeroProgress(),
    );
    final layout = const UpgradeLayout();
    final cx = layout.left + (layout.right - layout.left) * 0.5 / 3;
    expect(bar.hit(Offset(cx, layout.y)), 'strength');
  });

  test('skills take icons too', () {
    final w = _world();
    UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      iconAtlasId: 'icons',
      upgrades: const [],
      skills: const [
        HeroSkill(id: 'bolt', label: 'Bolt', kind: SkillKind.strike, icon: 3),
      ],
      progress: HeroProgress(),
    );
    expect(_spritesIn(w, 'icons'), 1);
  });

  test('an ultimate button shows the meter until it is full', () {
    final w = _world();
    const ult = HeroSkill(
      id: 'ult',
      label: 'Ult',
      kind: SkillKind.strike,
      ultimate: true,
    );
    final bar = UpgradeBar.spawn(
      w,
      atlasId: 'btn',
      upgrades: const [],
      skills: const [ult],
      progress: HeroProgress(),
    );
    List<String> texts() {
      final store = w.componentsOf<eng.Text>();
      return [for (var i = 0; i < store.length; i++) store.denseAt(i).text];
    }

    bar.syncSkills(w, SkillCooldowns(const [ult]), ultimate: 0.5);
    expect(texts(), contains('50%'));
    bar.syncSkills(w, SkillCooldowns(const [ult]), ultimate: 1);
    expect(texts(), isNot(contains('50%')));
    expect(texts(), contains(const WaveStrings().ready));
  });
}
