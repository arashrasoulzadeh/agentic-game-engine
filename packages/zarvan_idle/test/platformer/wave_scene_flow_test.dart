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
          hp: id == 'boss' ? 60 : (id == 'tank' ? 5000 : 30),
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
  SquadRule? squad,
  CombatTimingRules? timing,
  double windup = 0,
  double fightDelay = 0,
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
  squad: squad,
  timing: timing,
  windupSeconds: windup,
  fightDelaySeconds: fightDelay,
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

  group('the start of a fight', () {
    test(
      'no blow lands until the fight delay after the walk has passed',
      () async {
        final r = await _start(
          _Scene(level: _level(), config: _config(fightDelay: 4)),
        );
        final health = r.world.componentsOf<Health>();
        final hero = r.scene.heroId!;
        final start = health.get(hero)!.current;
        // The walk takes about 2.7 s, so by 4 s the delay is still running.
        r.run(4);
        expect(health.get(r.scene.enemyId!)!.current, greaterThan(0));
        expect(r.scene.progress.kills, 0);
        expect(health.get(hero)!.current, start);
        r.run(14);
        expect(r.scene.progress.kills, greaterThanOrEqualTo(1));
      },
    );
  });

  group('squads and player timing', () {
    List<EntityId> enemies(World w) {
      final roles = w.componentsOf<CombatRole>();
      final health = w.componentsOf<Health>();
      return [
        for (var i = 0; i < roles.length; i++)
          if (roles.denseAt(i).side == 'enemy' &&
              (health.get(roles.entityAt(i))?.current ?? 0) > 0)
            roles.entityAt(i),
      ];
    }

    const trio = SquadRule(oneExtraFromWave: 1, twoExtrasFromWave: 1);

    test(
      'a squad wave brings extras that stand behind the front enemy',
      () async {
        final r = await _start(
          _Scene(
            level: _level(),
            config: _config(squad: trio),
          ),
        );
        r.run(2.5);
        final all = enemies(r.world);
        expect(all, hasLength(3));
        final pos = r.world.componentsOf<Position>();
        final front = pos.get(r.scene.enemyId!)!;
        for (final id in all.where((e) => e != r.scene.enemyId)) {
          expect(pos.get(id)!.x, greaterThan(front.x));
          expect(pos.get(id)!.y, lessThan(front.y));
        }
      },
    );

    test('without a squad rule every wave is one-on-one', () async {
      final r = await _start(_Scene(level: _level(), config: _config()));
      r.run(2.5);
      expect(enemies(r.world), hasLength(1));
    });

    test(
      'the wave advances only when the whole squad is down; each pays',
      () async {
        final progress = HeroProgress();
        final r = await _start(
          _Scene(
            level: _level(),
            config: _config(squad: trio),
            progress: progress,
          ),
        );
        var steps = 0;
        while (progress.kills < 3 && steps++ < 400) {
          r.run(0.05);
        }
        expect(progress.kills, 3);
        // front pays 10, each extra ceil(10 x 0.6) = 6
        expect(progress.coins, 22);
      },
    );

    test('tapping a back-line enemy makes the hero fight it', () async {
      final r = await _start(
        _Scene(
          level: _level(),
          config: _config(squad: trio),
        ),
      );
      r.run(2.5);
      final front = r.scene.enemyId!;
      final back = enemies(r.world).firstWhere((e) => e != front);
      final at = r.world.componentsOf<Position>().get(back)!;
      r.tap(at.x, at.y);
      expect(r.scene.enemyId, back);
    });

    test('a tap in empty space does not change the target', () async {
      final r = await _start(
        _Scene(
          level: _level(),
          config: _config(squad: trio),
        ),
      );
      r.run(2.5);
      final front = r.scene.enemyId;
      r.tap(5, 5);
      expect(r.scene.enemyId, front);
    });

    test(
      'the next wave starts cleanly after a squad (no lost enemy)',
      () async {
        final progress = HeroProgress();
        final r = await _start(
          _Scene(
            level: _level(),
            config: _config(squad: trio),
            progress: progress,
          ),
        );
        r.run(15);
        expect(progress.kills, greaterThanOrEqualTo(6));
        final alive = enemies(r.world);
        expect(alive, isNotEmpty);
        final health = r.world.componentsOf<Health>();
        for (final e in alive) {
          expect(health.get(e)!.current, greaterThan(0));
          expect(r.world.componentsOf<CombatStats>().has(e), isTrue);
        }
      },
    );

    test('an area skill strikes the whole squad', () async {
      const blast = HeroSkill(
        id: 'b',
        label: 'B',
        kind: SkillKind.strike,
        power: 20,
        cooldown: 30,
        hitsAll: true,
      );
      final r = await _start(
        _Scene(
          level: _level(),
          config: _config(squad: trio, skills: const [blast]),
        ),
      );
      r.run(2.5);
      final before = enemies(r.world);
      expect(before, hasLength(3));
      r.tap(90, 262); // the skill button
      expect(enemies(r.world), isEmpty);
    });

    test('a tap while an enemy winds up parries it', () async {
      final parried = <AttackParried>[];
      final winding = <AttackWindup>[];
      final r = await _start(
        _Scene(
          level: _level(wave: ['tank']),
          config: _config(timing: const CombatTimingRules(), windup: 0.4),
        ),
      );
      r.world.events
        ..on<AttackParried>(parried.add)
        ..on<AttackWindup>(winding.add);
      for (var i = 0; i < 400 && parried.isEmpty; i++) {
        r.run(0.05);
        if (winding.any((w) => w.attackerSide == 'enemy') && parried.isEmpty) {
          r.tap(5, 5); // empty space: the parry tap
        }
      }
      expect(parried, hasLength(1));
    });

    test('taps do nothing without timing rules', () async {
      final parried = <AttackParried>[];
      final r = await _start(
        _Scene(
          level: _level(wave: ['tank']),
          config: _config(windup: 0.4),
        ),
      );
      r.world.events.on<AttackParried>(parried.add);
      for (var i = 0; i < 200; i++) {
        r.run(0.05);
        r.tap(5, 5);
      }
      expect(parried, isEmpty);
    });
  });
}
