import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:zarvan_core/zarvan_core.dart';
import 'package:zarvan_flutter/zarvan_flutter.dart' hide Text;
import 'package:zarvan_flutter/zarvan_flutter.dart'
    as eng
    show Text, TextAlignment;
import 'package:zarvan_platformer/zarvan_platformer.dart';

import '../combat/auto_combat_system.dart';
import '../combat/enemy_powers.dart';
import '../level/wave_plan.dart';
import '../fx/damage_numbers.dart';
import '../fx/hit_feedback.dart';
import '../hud/upgrade_bar.dart';
import '../progress/hero_progress.dart';
import 'scene_light.dart';
import 'sun_light.dart';
import '../combat/combat_components.dart';
import '../combat/fighter_death_system.dart';
import '../combat/spawn_fighter.dart';
import '../fighters/fighter_meta.dart';
import '../fx/combat_fx.dart';
import '../hud/dialogue_caption.dart';
import '../hud/hud_layout.dart';
import '../hud/scene_hud.dart';
import '../hud/sprite_health_bar.dart';
import '../hud/wave_path.dart';
import '../hud/wave_ui_art.dart';
import '../level/level_data.dart';
import '../level/wave_progress.dart';
import 'walk_phase.dart';

/// Where a [WaveCombatScene]'s art lives and how it plays. Everything a
/// second zone or game changes is here; the scene's behaviour is shared.
class WaveCombatConfig {
  const WaveCombatConfig({
    required this.heroStem,
    required this.enemyRoot,
    required this.backgroundDir,
    required this.backgroundPrefix,
    this.heroId = 'hero',
    this.hitFxStem,
    this.slashFxStem,
    this.deathFxStem,
    this.hitBurst = 6,
    this.fighterSize = 80,
    this.walkSpeed = 70,
    this.enterDistance = 190,
    this.deathHoldSeconds = 0.5,
    this.fallenMessage = 'The hero has fallen — tap to replay',
    this.clearedMessage = 'Cleared — tap to replay',
    this.bossLabel = 'Boss',
    this.impactParticles = defaultImpactParticles,
    this.hud = const HudLayout(),
    this.ui = const WaveUiArt(),
    this.sun,
    this.lights = const [],
    this.upgrades = const [],
    this.coinsPerKill = 10,
    this.bossCoins = 50,
    this.damageNumbers,
    this.hitFeedback,
    this.windupSeconds = 0,
    this.comboBonusPerHit = 0,
    this.comboMax = 10,
    this.waveSeed,
  });

  /// Asset stem of the hero sheets (`<stem>_idle.png`, `_attack`, `_death`).
  final String heroStem;
  final String heroId;

  /// Directory of enemy sheets: `<enemyRoot>/<id>_idle.png` and so on.
  final String enemyRoot;

  /// Directory of parallax layer images `<name>.png`, registered as atlas
  /// `<backgroundPrefix>_<name>`.
  final String backgroundDir;
  final String backgroundPrefix;

  /// Effect sheet stems (null skips that effect).
  final String? hitFxStem;
  final String? slashFxStem;
  final String? deathFxStem;

  /// Particles bursting from a fighter each time it is hit (0 off).
  final int hitBurst;

  /// Every fighter is drawn this many world units square whatever its sheet's
  /// cell, so high-resolution sheets and small ones stand the same size.
  final double fighterSize;

  final double walkSpeed;
  final double enterDistance;

  /// How long a finished death clip lingers before the scene moves on.
  final double deathHoldSeconds;

  final String fallenMessage;
  final String clearedMessage;

  /// HUD caption for the boss encounter.
  final String bossLabel;

  /// Where the HUD's labels and health bars sit and their colours.
  final HudLayout hud;

  /// Generated UI art for the bars, path and caption (each optional).
  final WaveUiArt ui;

  /// A sun-like light over the scene; null (default) leaves it unlit.
  final SunLight? sun;

  /// Extra lights: lanterns, glows, torches (see [SceneLight]). Without a
  /// [sun] the scene is not darkened, so they only add tint.
  final List<SceneLight> lights;

  /// Hero upgrades the player can buy with coins (needs
  /// `WaveUiArt.buttonImage` for the buttons). Empty (default) means none.
  final List<HeroUpgrade> upgrades;

  /// Coins for each enemy killed, and for the boss.
  final int coinsPerKill;
  final int bossCoins;

  /// Floating damage numbers on hits; null (default) shows none.
  final DamageNumberStyle? damageNumbers;

  /// Knockback, red screen flash, camera shake and critical sparks; null
  /// (default) adds none.
  final HitFeedback? hitFeedback;

  /// Seconds before an attack that it is telegraphed (see
  /// `HitFeedback.windupTintArgb`); 0 (default) means no wind-up.
  final double windupSeconds;

  /// Combo: every consecutive hero hit (a hit taken resets it) adds this
  /// fraction of damage, up to [comboMax] hits. 0 (default) turns combos off.
  final double comboBonusPerHit;
  final int comboMax;

  /// Seeds the random wave order (`LevelData.randomWaves`); null = a fresh
  /// order every run.
  final int? waveSeed;

  /// Builds the spark emitter each fighter gets.
  final ParticleEmitter Function() impactParticles;

  /// Sparks that spread from a fighter when it is hit.
  static ParticleEmitter defaultImpactParticles() => ParticleEmitter(
    speedMin: 25,
    speedMax: 70,
    lifetimeMin: 0.2,
    lifetimeMax: 0.45,
    startScale: 1.6,
    colorArgb: 0xFFFFD27A,
    zIndex: 35,
    emissionShape: EmissionShape.circle,
    emissionRadius: 6,
  );
}

/// A portrait idle-combat scene: the hero walks (scenery scrolling in
/// parallax), meets the next enemy of a [LevelData] wave, auto-fights it, and
/// walks on, ending with the boss. Combat, animation states, pivots, effects,
/// shake/particle cues and the walk are engine systems this scene registers;
/// a game supplies a [LevelData] and a [WaveCombatConfig].
class WaveCombatScene extends Scene {
  WaveCombatScene({
    required this.level,
    required this.config,
    HeroProgress? progress,
  }) : progress = progress ?? HeroProgress();

  final LevelData level;
  final WaveCombatConfig config;

  /// Coins and upgrade levels. Pass the same object to the next scene (a
  /// retry) to keep them.
  final HeroProgress progress;

  static const _hitFx = 'fx_hit';
  static const _slashFx = 'fx_slash';
  static const _deathFx = 'fx_death';
  static const _uiBars = 'ui_bars';
  static const _uiNodes = 'ui_path_nodes';
  static const _uiLine = 'ui_path_line';
  static const _uiScroll = 'ui_caption_scroll';
  static const _uiButtons = 'ui_buttons';

  late final WavePlan plan = WavePlan.generate(
    level,
    math.Random(config.waveSeed ?? DateTime.now().microsecondsSinceEpoch),
  );
  late final WaveProgress waves = WaveProgress(
    wave: plan.ids,
    boss: level.boss,
  );
  late final Map<String, String> _fxStems = {
    if (config.hitFxStem != null) _hitFx: config.hitFxStem!,
    if (config.slashFxStem != null) _slashFx: config.slashFxStem!,
    if (config.deathFxStem != null) _deathFx: config.deathFxStem!,
  };
  late SceneHud _hud;
  late DialogueCaption _caption;
  late WalkPhase _walk;
  late Camera _camera;
  final _combat = AutoCombatSystem();
  final _pivots = PivotTable();
  final Map<String, FighterMeta> _meta = {};
  EntityId? heroId;
  EntityId? enemyId;
  EntityId? _enemyHudId;
  SpriteHealthBar? _heroBar;
  SpriteHealthBar? _enemyBar;
  WavePath? _path;
  EntityId? _corpse;
  SceneController? _scenes;

  bool finished = false;
  bool _heroFell = false;
  bool _enemyRewarded = false;
  int _rewardCoins = 0;
  int _combo = 0;
  EntityId? _comboLabel;
  HitStop? _hitStop;
  UpgradeBar? _upgradeBar;
  late double _baseHp, _baseAttack, _baseAttackSpeed, _baseArmor;
  late String status = level.name;
  String enemyLabel = '';
  String enemyDescription = '';

  double _enemyTargetX = 0;
  double _enemyBaseY = 0;
  double _deathHold = 0;

  @override
  bool get showOnScreenControls => false;

  String _enemyStem(String id) => '${config.enemyRoot}/$id';

  double _fitScale(double cell) => config.fighterSize / cell;

  @override
  Future<void> populate(
    World world,
    SceneController scenes,
    GameState state,
  ) async {
    _scenes = scenes;
    registerPlatformerComponents(world);
    registerCombatComponents(world);
    registerDamageNumberComponents(world);
    registerHitFeedbackComponents(world);
    registerWindupComponents(world);
    world
      ..addSystem(_combat)
      ..addSystem(TweenSystem())
      ..addSystem(MovementSystem())
      ..addSystem(ParticleSystem())
      ..addSystem(HitFlashSystem())
      ..addSystem(HealthSystem())
      ..addSystem(HealthHudSystem())
      ..addSystem(FighterDeathSystem())
      ..addSystem(SpriteStateSystem())
      ..addSystem(AnimationSystem())
      ..addSystem(SpritePivotSystem(_pivots))
      ..addSystem(OneShotFxSystem())
      ..addSystem(DamageNumberSystem())
      ..addSystem(HitFeedbackSystem());

    _camera = Camera(x: world.width / 2, y: world.height / 2);
    // Shake / particle cues authored in the level JSON fire from animation
    // frames through the engine's cue bridges.
    installAnimationCueSystems(world, camera: _camera);
    _walk = WalkPhase(
      scroller: ParallaxScroller.spawn(
        world,
        config.backgroundPrefix,
        level.parallax,
      ),
      speed: config.walkSpeed,
      distance: config.enterDistance,
    );
    Future<FxClip?> fx(String id) async =>
        _fxStems.containsKey(id) ? loadFxClip(id, _fxStems[id]!) : null;
    installCombatFx(
      world,
      CombatFx(
        hit: await fx(_hitFx),
        slash: await fx(_slashFx),
        death: await fx(_deathFx),
        hitBurst: config.hitBurst,
      ),
      pivots: _pivots,
    );
    final numbers = config.damageNumbers;
    if (numbers != null) installDamageNumbers(world, numbers);
    final feedback = config.hitFeedback;
    if (feedback != null) {
      _hitStop = HitStop(world);
      installHitFeedback(
        world,
        feedback,
        _camera,
        hitStop: _hitStop,
        warningStyle: numbers ?? const DamageNumberStyle(),
      );
    }
    _combat.windupSeconds = config.windupSeconds;
    if (config.comboBonusPerHit > 0) {
      _comboLabel = world.spawn();
      world.componentsOf<Position>().set(_comboLabel!, Position(145, 64));
      world.componentsOf<eng.Text>().set(
        _comboLabel!,
        eng.Text(
          '',
          fontSize: 5.4,
          colorArgb: 0xFFFFC93C,
          align: eng.TextAlignment.center,
          screenSpace: false,
          zIndex: 125,
        ),
      );
      _combat.damageMultiplier = (side) => side == 'hero'
          ? 1 + math.min(_combo, config.comboMax) * config.comboBonusPerHit
          : 1;
      world.events.on<FighterHit>((hit) {
        _combo = hit.attackerSide == 'hero' ? _combo + 1 : 0;
        _syncCombo(world);
      });
    }

    _meta[config.heroId] = await FighterMeta.load(
      config.heroId,
      config.heroStem,
    );
    for (final id in level.enemyIds) {
      _meta[id] = await FighterMeta.load(id, _enemyStem(id));
    }

    _spawnHero(world);
    _hud = SceneHud.spawn(world, status: status, layout: config.hud);
    final ui = config.ui;
    _caption = DialogueCaption.spawn(
      world,
      style: config.hud.description,
      backdropAtlasId: ui.captionBackdropImage == null ? null : _uiScroll,
      backdropWidth: ui.captionBackdropWidth,
      backdropHeight: ui.captionBackdropHeight,
    );
    if (ui.pathNodesStem != null) {
      _path = WavePath.spawn(
        world,
        nodesAtlasId: _uiNodes,
        lineAtlasId: ui.pathLineImage == null ? null : _uiLine,
        count: level.wave.length + 1,
        y: ui.pathY,
        left: ui.pathInset,
        right: world.width - ui.pathInset,
        nodeSize: ui.pathNodeSize,
      );
    }
    final sun = config.sun;
    if (sun != null) {
      final id = world.spawn();
      world.componentsOf<Position>().set(id, Position(sun.x, sun.y));
      world.componentsOf<Light2D>().set(
        id,
        Light2D(
          radius: sun.radius,
          intensity: sun.intensity,
          colorArgb: sun.colorArgb,
        ),
      );
    }
    if (config.lights.isNotEmpty) {
      final ids = <EntityId>[];
      for (final spec in config.lights) {
        final id = world.spawn();
        world.componentsOf<Position>().set(id, Position(spec.x, spec.y));
        world.componentsOf<Light2D>().set(
          id,
          Light2D(
            radius: spec.radius,
            intensity: spec.intensity,
            colorArgb: spec.colorArgb,
          ),
        );
        ids.add(id);
      }
      world.addSystem(
        SceneLightSystem(config.lights, ids, () => heroId, () => enemyId),
      );
    }
    if (config.upgrades.isNotEmpty && config.ui.buttonImage != null) {
      _upgradeBar = UpgradeBar.spawn(
        world,
        atlasId: _uiButtons,
        upgrades: config.upgrades,
        progress: progress,
        layout: config.ui.upgradeLayout,
      );
    }
    _spawnEnemy(world);
  }

  @override
  double? get ambientBrightness => config.sun?.ambientBrightness;

  @override
  Future<AtlasRegistry> loadAssets() async {
    final registry = AtlasRegistry();
    final ui = config.ui;
    final total =
        level.parallax.length +
        _meta.length * FighterMeta.states.length +
        _fxStems.length +
        (ui.barsStem != null ? 1 : 0) +
        (ui.pathNodesStem != null ? 1 : 0) +
        (ui.pathLineImage != null ? 1 : 0) +
        (ui.captionBackdropImage != null ? 1 : 0) +
        (ui.buttonImage != null ? 1 : 0);
    var done = 0;
    void loaded() => reportAssetProgress(++done, total);
    for (final layer in level.parallax) {
      registry.register(
        layer.atlasId(config.backgroundPrefix),
        await SpriteAtlas.loadFullImageFromAssets(
          '${config.backgroundDir}/${layer.name}.png',
        ),
      );
      loaded();
    }
    for (final meta in _meta.values) {
      for (final state in FighterMeta.states) {
        final sheet = await loadSpriteSheet(meta.stem(state));
        registry.register(meta.atlasId(state), sheet.atlas);
        _pivots.register(
          meta.atlasId(state),
          sheet.pivots,
          cell: sheet.sidecar.cell.toDouble(),
        );
        loaded();
      }
    }
    for (final e in _fxStems.entries) {
      registry.register(
        e.key,
        (await loadSpriteSheet(e.value, measurePivots: false)).atlas,
      );
      loaded();
    }
    if (ui.barsStem != null) {
      registry.register(_uiBars, await BarsArt.load(ui.barsStem!));
      loaded();
    }
    if (ui.pathNodesStem != null) {
      registry.register(
        _uiNodes,
        (await loadSpriteSheet(ui.pathNodesStem!, measurePivots: false)).atlas,
      );
      loaded();
    }
    if (ui.pathLineImage != null) {
      registry.register(
        _uiLine,
        await SpriteAtlas.loadFullImageFromAssets(ui.pathLineImage!),
      );
      loaded();
    }
    if (ui.captionBackdropImage != null) {
      registry.register(
        _uiScroll,
        await SpriteAtlas.loadFullImageFromAssets(ui.captionBackdropImage!),
      );
      loaded();
    }
    if (ui.buttonImage != null) {
      registry.register(
        _uiButtons,
        UpgradeBar.atlasFor(
          await SpriteAtlas.loadFullImageFromAssets(ui.buttonImage!),
        ),
      );
      loaded();
    }
    return registry;
  }

  @override
  Camera createCamera(World world) => _camera;

  void _spawnHero(World world) {
    final meta = _meta[config.heroId]!;
    final hs = meta.stats;
    final scale = _fitScale(hs.cell);
    final drawn = hs.cell * scale;
    _baseHp = level.scaled('hp', hs.hp);
    _baseAttack = level.scaled('attack', hs.attack);
    _baseAttackSpeed = level.scaled('attack_speed', hs.attackSpeed);
    _baseArmor = level.scaled('armor', hs.armor);
    double up(String stat) => progress.multiplier(stat, config.upgrades);
    heroId = spawnFighter(
      world,
      side: 'hero',
      x: level.hero.x + drawn / 2,
      y: level.hero.y + drawn / 2,
      hp: _baseHp * up('hp'),
      attack: _baseAttack * up('attack'),
      attackSpeed: _baseAttackSpeed * up('attack_speed'),
      armor: _baseArmor * up('armor'),
      critChance: level.heroCritChance,
      critMultiplier: level.heroCritMultiplier,
      atlasId: meta.atlasId('idle'),
      frameCount: meta.frames['idle']!,
      extraClips: meta.extraClips(cues: level.cues),
      impactParticles: config.impactParticles(),
      scaleX: scale,
      scaleY: scale,
      // The hero draws in front of enemies and the corpse sliding past him.
      zIndex: 25,
    );
    final bar = config.hud.heroBar;
    if (config.ui.barsStem != null) {
      _heroBar = SpriteHealthBar.spawn(
        world,
        atlasId: _uiBars,
        source: heroId!,
        left: bar.x,
        top: bar.y,
        width: bar.width,
        fill: 'xp',
      );
    } else {
      spawnHealthHudBar(
        world,
        source: heroId!,
        x: bar.x,
        y: bar.y,
        width: bar.width,
        height: bar.height,
        fillColorArgb: bar.fillColorArgb,
        screenSpace: false,
        zIndex: 100,
      );
    }
  }

  /// Brings the next enemy in from off-screen; combat starts once it has
  /// walked up to its anchor. The previous one stays as a corpse that
  /// scrolls away with the ground.
  void _spawnEnemy(World world) {
    _enemyRewarded = false;
    if (_corpse != null) world.destroy(_corpse!);
    _corpse = enemyId;
    if (_enemyHudId != null) world.destroy(_enemyHudId!);
    _enemyBar?.destroy();

    final meta = _meta[waves.currentId]!;
    final stats = meta.stats;
    status = waves.isBoss ? config.bossLabel : waves.label;
    final kind = waves.isBoss ? WaveKind.normal : plan.kinds[waves.index];
    final rw = level.randomWaves;
    final hpKind = switch (kind) {
      WaveKind.elite => rw?.eliteHp ?? 1,
      WaveKind.treasure => rw?.treasureHp ?? 1,
      WaveKind.normal => 1.0,
    };
    final attackKind = switch (kind) {
      WaveKind.elite => rw?.eliteAttack ?? 1,
      WaveKind.treasure => rw?.treasureAttack ?? 1,
      WaveKind.normal => 1.0,
    };
    final sizeKind = kind == WaveKind.elite ? (rw?.eliteScale ?? 1) : 1.0;
    _rewardCoins = waves.isBoss
        ? config.bossCoins
        : switch (kind) {
            WaveKind.elite => config.coinsPerKill * (rw?.eliteCoins ?? 1),
            WaveKind.treasure => config.coinsPerKill * (rw?.treasureCoins ?? 1),
            WaveKind.normal => config.coinsPerKill,
          };
    final scale = _fitScale(stats.cell) * sizeKind;
    final drawn = stats.cell * scale;
    _enemyTargetX = level.enemyAnchor.x + drawn / 2;
    _enemyBaseY = level.enemyAnchor.y + drawn / 2;
    enemyId = spawnFighter(
      world,
      side: 'enemy',
      x: _enemyTargetX + config.enterDistance,
      y: _enemyBaseY,
      hp: waves.isBoss
          ? level.bossScaled('hp', stats.hp)
          : stats.hp * level.enemyRamp(waves.index) * hpKind,
      attack: waves.isBoss
          ? level.bossScaled('attack', stats.attack)
          : stats.attack * level.enemyRamp(waves.index) * attackKind,
      attackSpeed: stats.attackSpeed,
      armor: stats.armor,
      powers: kind == WaveKind.treasure
          ? null
          : EnemyPowers.parse(stats.powers),
      atlasId: meta.atlasId('idle'),
      frameCount: meta.frames['idle']!,
      extraClips: meta.extraClips(cues: level.cues),
      impactParticles: config.impactParticles(),
      // Sheets already face the hero (leftward); do not mirror.
      scaleX: scale,
      scaleY: scale,
      zIndex: 20,
    );
    final bar = config.hud.enemyBar;
    if (config.ui.barsStem != null) {
      _enemyBar = SpriteHealthBar.spawn(
        world,
        atlasId: _uiBars,
        source: enemyId!,
        left: bar.x,
        top: bar.y,
        width: bar.width,
        fill: waves.isBoss ? 'boss' : 'hp',
      );
    } else {
      _enemyHudId = spawnHealthHudBar(
        world,
        source: enemyId!,
        x: bar.x,
        y: bar.y,
        width: bar.width,
        height: bar.height,
        fillColorArgb: waves.isBoss
            ? config.hud.bossBarColorArgb
            : bar.fillColorArgb,
        screenSpace: false,
        zIndex: 100,
      );
    }
    _path?.update(waves.index, config.ui.pathNodeSize);
    enemyLabel = switch (kind) {
      WaveKind.elite => 'Elite ${meta.name}',
      WaveKind.treasure => 'Golden ${meta.name}',
      WaveKind.normal => meta.name,
    };
    enemyDescription = meta.descriptionFa;
    _combat.enabled = false;
    _walk.start(world, hero: heroId!, enemy: enemyId!, corpse: _corpse);
    _caption.show(world, enemyDescription);
    _syncHud(world);
  }

  void _syncHud(World world) =>
      _hud.sync(world, status: status, enemy: enemyLabel);

  void _finish(World world, String message) {
    finished = true;
    status = message;
    _caption.hide();
    _syncHud(world);
    if (_heroFell) _upgradeBar?.showRetry(world);
  }

  /// Re-derives the living hero's stats from the base values and the bought
  /// upgrade levels, keeping the health fraction it already has.
  void _applyUpgrades(World world) {
    final h = heroId;
    if (h == null) return;
    double up(String stat) => progress.multiplier(stat, config.upgrades);
    final stats = world.componentsOf<CombatStats>();
    final health = world.componentsOf<Health>().get(h);
    final old = stats.get(h);
    if (old == null || health == null) return;
    final maxHp = _baseHp * up('hp');
    final fraction = health.max <= 0 ? 1.0 : health.current / health.max;
    stats.set(
      h,
      CombatStats(
        maxHp: maxHp,
        attack: _baseAttack * up('attack'),
        attackSpeed: _baseAttackSpeed * up('attack_speed'),
        armor: _baseArmor * up('armor'),
        cooldown: old.cooldown,
        critChance: old.critChance,
        critMultiplier: old.critMultiplier,
      ),
    );
    health
      ..max = maxHp
      ..current = maxHp * fraction;
  }

  /// True once [fighter]'s death clip has finished and lingered for a beat.
  bool _deathPlayed(World world, EntityId fighter, double dt) {
    if (!spriteStateFinished(world, fighter, 'death')) return false;
    _deathHold += dt;
    if (_deathHold < config.deathHoldSeconds) return false;
    _deathHold = 0;
    return true;
  }

  void _syncCombo(World world) {
    final id = _comboLabel;
    if (id == null) return;
    world.componentsOf<eng.Text>().get(id)?.text = _combo >= 2
        ? 'Combo x$_combo'
        : '';
  }

  @override
  void update(double dt, World world) {
    _hitStop?.update(dt);
    _caption.update(world, dt);
    _heroBar?.sync();
    _enemyBar?.sync();
    if (finished) return;
    final h = heroId;
    final e = enemyId;
    if (h == null || e == null) return;

    if (_walk.active) {
      if (_walk.update(world)) {
        _corpse = null;
        _combat.enabled = true;
      }
      return;
    }

    final heroHp = world.componentsOf<Health>().get(h);
    final enemyHp = world.componentsOf<Health>().get(e);
    if (heroHp != null && heroHp.current <= 0) {
      if (!_deathPlayed(world, h, dt)) return;
      _heroFell = true;
      return _finish(world, config.fallenMessage);
    }
    if (enemyHp != null && enemyHp.current <= 0) {
      // The description stays up for the whole encounter and goes with the enemy.
      _caption.hide();
      if (!_enemyRewarded) {
        _enemyRewarded = true;
        progress.coins += _rewardCoins;
        _upgradeBar?.sync(world);
      }
      if (!_deathPlayed(world, e, dt)) return;
      if (waves.isBoss) return _finish(world, config.clearedMessage);
      waves.advance();
      _spawnEnemy(world);
    }
  }

  @override
  void handleTap(World world, SceneController scenes, Offset worldPosition) {
    final bar = _upgradeBar;
    final pressed = bar?.hit(worldPosition);
    if (pressed == UpgradeBar.retryAction) return _restart(scenes);
    if (pressed != null) {
      final upgrade = config.upgrades.firstWhere((u) => u.id == pressed);
      if (progress.buy(upgrade)) {
        _applyUpgrades(world);
        bar!.sync(world);
      }
      return;
    }
    if (!finished) return;
    // A lost run with a retry button restarts only from that button; a win,
    // or a scene without buttons, replays on any tap.
    if (_heroFell && bar != null) return;
    _restart(scenes);
  }

  void _restart(SceneController scenes) => (_scenes ?? scenes).loadScene(
    WaveCombatScene(level: level, config: config, progress: progress),
  );
}
