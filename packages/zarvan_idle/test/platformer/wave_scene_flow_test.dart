import 'package:flutter_test/flutter_test.dart';
import 'package:zarvan_core/zarvan_core.dart' hide StatusEffect, StatusEffects;
import 'package:zarvan_flutter/zarvan_flutter.dart' as eng;
import 'package:zarvan_idle/zarvan_idle.dart';
import 'package:zarvan_platformer/zarvan_platformer.dart';

/// A scene with no assets: fighters come from [_meta] and nothing is drawn.
class _Scene extends WaveCombatScene {
  _Scene({required super.level, required super.config, super.progress})
    : super(metaLoader: _meta);

  @override
  Future<eng.AtlasRegistry> loadAssets() async => eng.AtlasRegistry();
}

Future<FighterMeta> _meta(String id, String stem) async => FighterMeta(
  id: id,
  name: id,
  stemPrefix: stem,
  frames: const {'idle': 1, 'attack': 1, 'death': 1},
  stats: id == 'hero'
      ? FighterStats(hp: 500, attack: 40, attackSpeed: 2, armor: 0)
      : FighterStats(
          hp: id == 'boss' ? 60 : 30,
          attack: 2,
          attackSpeed: 1,
          armor: 0,
          powers: id == 'bleeder'
              ? const ['hits apply bleed: 2% hero max hp/s for 3s']
              : const [],
        ),
);

LevelData _level({List<String>? wave, Map<String, dynamic> extra = const {}}) =>
    LevelData.fromJson({
      'name': 'L',
      'wave': wave ?? ['a', 'b', 'c', 'd', 'e', 'f'],
      'boss': 'boss',
      'background': 'x',
      'hero': {'x': 10, 'y': 200},
      'enemy_anchor': {'x': 100, 'y': 200},
      ...extra,
    });

const _strength = HeroUpgrade(
  id: 's',
  label: 'S',
  stat: 'attack',
  perLevel: 0.5,
  baseCost: 5,
);

WaveCombatConfig _config({
  List<HeroUpgrade> upgrades = const [_strength],
  List<HeroSkill> skills = const [],
  LootTable? loot,
  int checkpointEvery = 0,
  double prestige = 0,
}) => WaveCombatConfig(
  heroStem: 'hero',
  enemyRoot: 'enemies',
  backgroundDir: 'bg',
  backgroundPrefix: 'bg',
  ui: const WaveUiArt(buttonImage: 'btn.png'),
  upgrades: upgrades,
  skills: skills,
  loot: loot,
  checkpointEvery: checkpointEvery,
  prestigeBonusPerStar: prestige,
  coinsPerKill: 10,
  bossCoins: 50,
  deathHoldSeconds: 0.1,
  waveSeed: 1,
);

class _Run {
  _Run(this.scene, this.world, this.loaded);

  final _Scene scene;
  final World world;
  final List<eng.Scene> loaded;

  void run(double seconds, {double dt = 0.05}) {
    for (var t = 0.0; t < seconds; t += dt) {
      world.step(dt);
      scene.update(dt, world);
    }
  }

  void tap(double x, double y) =>
      scene.handleTap(world, eng.SceneController(), Offset(x, y));
}

Future<_Run> _start(_Scene scene) async {
  final world = World(width: 180, height: 320);
  registerCoreComponents(world);
  eng.registerFlutterComponents(world);
  final loaded = <eng.Scene>[];
  final controller = eng.SceneController()
    ..attach(loadScene: loaded.add, pushOverlay: (_) {}, popOverlay: () {});
  await scene.populate(world, controller, GameState());
  return _Run(scene, world, loaded);
}

void main() {
  test(
    'killing an enemy pays coins, counts the kill and advances the wave',
    () async {
      final progress = HeroProgress();
      final r = await _start(
        _Scene(level: _level(), config: _config(), progress: progress),
      );
      r.run(12);
      expect(progress.kills, greaterThanOrEqualTo(1));
      expect(progress.coins, greaterThanOrEqualTo(10));
      expect(progress.bestWave, greaterThanOrEqualTo(1));
      expect(r.scene.waves.index, greaterThanOrEqualTo(1));
    },
  );

  test(
    'buying an upgrade mid-fight raises the living hero and spends coins',
    () async {
      final progress = HeroProgress(coins: 20);
      final r = await _start(
        _Scene(level: _level(), config: _config(), progress: progress),
      );
      final stats = r.world.componentsOf<CombatStats>();
      final hero = r.scene.heroId!;
      final before = stats.get(hero)!.attack;
      // The first upgrade button is the only one: centred at x=90, y=296.
      r.tap(90, 296);
      expect(progress.levelOf(_strength), 1);
      expect(progress.coins, 15);
      expect(stats.get(hero)!.attack, closeTo(before * 1.5, 1e-9));
    },
  );

  test(
    'a lost run shows Retry and a summary; Retry keeps coins and upgrades',
    () async {
      final progress = HeroProgress(coins: 99)..buy(_strength);
      final r = await _start(
        _Scene(level: _level(), config: _config(), progress: progress),
      );
      final hero = r.scene.heroId!;
      r.world.componentsOf<Health>().get(hero)!.current = 0;
      r.run(6);
      expect(r.scene.finished, isTrue);
      expect(r.loaded, isEmpty);
      r.tap(5, 5); // anywhere but a button does nothing with buttons present
      expect(r.loaded, isEmpty);
      r.tap(90, 196); // the Retry button
      expect(r.loaded.single, isA<WaveCombatScene>());
      expect(progress.levelOf(_strength), 1);
      expect(progress.coins, 94);
      final next = r.loaded.single as WaveCombatScene;
      expect(identical(next.progress, progress), isTrue);
    },
  );

  test('a new run starts at the checkpoint of the best wave', () async {
    final progress = HeroProgress()..bestWave = 7;
    final r = await _start(
      _Scene(
        level: _level(wave: List.generate(12, (i) => 'w$i')),
        config: _config(checkpointEvery: 5),
        progress: progress,
      ),
    );
    expect(r.scene.waves.index, 5);
    expect(progress.runs, 1);
  });

  test(
    'clearing the boss offers Ascend; it adds a star and resets coins',
    () async {
      final progress = HeroProgress(coins: 77)..bestWave = 3;
      final r = await _start(
        _Scene(
          level: _level(wave: ['a']),
          config: _config(prestige: 0.25),
          progress: progress,
        ),
      );
      r.run(40);
      expect(r.scene.finished, isTrue);
      r.tap(90, 196 + 35); // the Ascend button sits under Retry
      expect(progress.stars, 1);
      expect(progress.coins, 0);
      expect(r.loaded.single, isA<WaveCombatScene>());
    },
  );

  test('a ready skill strikes the enemy hard, then cools down', () async {
    const skill = HeroSkill(
      id: 'x',
      label: 'X',
      kind: SkillKind.strike,
      power: 5,
      cooldown: 30,
    );
    final r = await _start(
      _Scene(
        level: _level(),
        config: _config(skills: const [skill]),
        progress: HeroProgress(),
      ),
    );
    r.run(2); // let the first enemy arrive
    final enemy = r.scene.enemyId!;
    final hp = r.world.componentsOf<Health>().get(enemy)!;
    final before = hp.current;
    r.tap(90, 262); // the skill button
    expect(hp.current, lessThan(before));
    final after = hp.current;
    r.tap(90, 262); // still cooling down
    expect(hp.current, after);
  });

  test('an enemy with bleed shows the condition over the hero', () async {
    final r = await _start(
      _Scene(
        level: _level(wave: ['bleeder', 'bleeder']),
        config: _config(),
        progress: HeroProgress(),
      ),
    );
    r.run(6);
    final hero = r.scene.heroId!;
    final texts = r.world.componentsOf<eng.Text>();
    final lines = [
      for (var i = 0; i < texts.length; i++) texts.denseAt(i).text,
    ];
    expect(r.world.componentsOf<Conditions>().has(hero), isTrue);
    expect(lines.any((t) => t.startsWith('Bleed')), isTrue);
  });

  test('worn gear raises the hero and the loot message appears', () async {
    const table = LootTable(normalChance: 1, eliteChance: 1);
    final progress = HeroProgress();
    final r = await _start(
      _Scene(
        level: _level(),
        config: _config(loot: table),
        progress: progress,
      ),
    );
    r.run(12);
    expect(progress.gear, isNotEmpty);
    final texts = r.world.componentsOf<eng.Text>();
    final lines = [
      for (var i = 0; i < texts.length; i++) texts.denseAt(i).text,
    ];
    expect(lines.any((t) => t.startsWith('Loot:')), isTrue);
  });

  test('first-run hints show once and are remembered', () async {
    final progress = HeroProgress();
    var r = await _start(
      _Scene(level: _level(), config: _config(), progress: progress),
    );
    List<String> lines(_Run run) {
      final t = run.world.componentsOf<eng.Text>();
      return [for (var i = 0; i < t.length; i++) t.denseAt(i).text];
    }

    expect(lines(r), contains(const WaveStrings().hintUpgrade));
    r = await _start(
      _Scene(level: _level(), config: _config(), progress: progress),
    );
    expect(lines(r), isNot(contains(const WaveStrings().hintUpgrade)));
  });

  test('offline coins are announced once and cleared', () async {
    final progress = HeroProgress()
      ..pendingOfflineCoins = 123
      ..pendingOfflineAway = const Duration(hours: 2);
    final r = await _start(
      _Scene(level: _level(), config: _config(), progress: progress),
    );
    final t = r.world.componentsOf<eng.Text>();
    final lines = [for (var i = 0; i < t.length; i++) t.denseAt(i).text];
    expect(lines, contains('+123 coins earned while away'));
    expect(progress.pendingOfflineCoins, 0);
  });
}
