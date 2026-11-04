import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/src/register_components.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' as eng show Sprite, Text;
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
